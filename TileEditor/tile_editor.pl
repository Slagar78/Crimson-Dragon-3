use strict;
use warnings;
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

BEGIN { $ENV{PATH} .= ';C:\Strawberry\perl\vendor\lib\SDL2'; }

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

# SDL функции
$ffi->attach( SDL_Init               => ['uint']                     => 'int' );
$ffi->attach( SDL_GetError           => []                           => 'string' );
$ffi->attach( SDL_SetHint            => ['string', 'string']         => 'int' );
$ffi->attach( SDL_CreateWindow       => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer     => ['opaque','int','uint']      => 'opaque' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque']    => 'opaque' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear        => ['opaque']                   => 'int' );
$ffi->attach( SDL_RenderCopy         => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent      => ['opaque']                   => 'void' );
$ffi->attach( SDL_PollEvent          => ['opaque']                   => 'int' );
$ffi->attach( SDL_Delay              => ['uint']                     => 'void' );
$ffi->attach( SDL_DestroyRenderer    => ['opaque']                   => 'void' );
$ffi->attach( SDL_DestroyWindow      => ['opaque']                   => 'void' );
$ffi->attach( SDL_Quit               => []                           => 'void' );
$ffi->attach( SDL_FreeSurface        => ['opaque']                   => 'void' );
$ffi->attach( SDL_RenderDrawLine     => ['opaque', 'int', 'int', 'int', 'int'] => 'int' );
$ffi->attach( SDL_RenderDrawRect     => ['opaque', 'opaque']         => 'int' );
$ffi->attach( SDL_RenderFillRect     => ['opaque', 'opaque']         => 'int' );
$ffi->attach( SDL_CreateRGBSurface   => ['uint','int','int','int','int','uint','uint','uint','uint'] => 'opaque' );
$ffi->attach( SDL_MapRGBA            => ['opaque','uint8','uint8','uint8','uint8'] => 'uint' );
$ffi->attach( SDL_FillRect           => ['opaque','opaque','uint']   => 'int' );

# SDL_image
$ffi->attach( IMG_Load                => ['string']                  => 'opaque' );
$ffi->attach( IMG_Init                => ['int']                     => 'int' );

# Инициализация
die "SDL_Init: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init: " . SDL_GetError() unless IMG_Init(2) & 2;
SDL_SetHint("SDL_HINT_RENDER_SCALE_QUALITY", "0");  # nearest neighbour

# ---------- НАСТРОЙКИ ----------
my $SCALE        = 3;
my $TILE_SIZE    = 8;
my $MAP_COLS     = 31;
my $MAP_ROWS     = 20;
my $MAP_OFF_X    = 4;
my $MAP_OFF_Y    = 4;
my $MAP_W        = ($MAP_OFF_X + $MAP_COLS * $TILE_SIZE) * $SCALE;
my $MAP_H        = ($MAP_OFF_Y + $MAP_ROWS * $TILE_SIZE) * $SCALE;

my $PAL_COLS     = 16;                # тайлов в ряду палитры
my $PAL_TILE_W   = $TILE_SIZE * $SCALE;
my $PAL_TILE_H   = $TILE_SIZE * $SCALE;
my $PAL_WIDTH    = $PAL_COLS * $PAL_TILE_W;   # 384
my $SCROLLBAR_W  = 16;
my $PAL_PANEL_W  = $PAL_WIDTH + $SCROLLBAR_W; # 400

my $TOP_BAR_H    = 50;                # высота панели с кнопками
my $PAL_AREA_H   = 600;
my $LEFT_PANEL_H = $TOP_BAR_H + $PAL_AREA_H;

my $WIN_W = $PAL_PANEL_W + $MAP_W;   # 400 + 756 = 1156
my $WIN_H = $LEFT_PANEL_H > $MAP_H ? $LEFT_PANEL_H : $MAP_H;
$WIN_H = 650 if $WIN_H < 650;

my $TS_COLS      = 64;
my $TS_ROWS      = 64;
my $TOTAL_TILES  = $TS_COLS * $TS_ROWS;
my $TILESET_FILE = "../assets/map/tileset.png";

# Карта
my @map;
if (-f "../assets/map/map01.txt") {
    open(my $fh, '<', "../assets/map/map01.txt") or die;
    while (<$fh>) { chomp; s/^\s+//; s/\s+$//; next if $_ eq ''; my @row = split /\s+/, $_; push @map, \@row; }
    close $fh;
    print "Карта загружена.\n";
} else {
    for (0..$MAP_ROWS-1) { push @map, [(0) x $MAP_COLS]; }
    print "Новая карта.\n";
}

# Окно и рендерер
my $window   = SDL_CreateWindow("Tile Map Editor", 100, 100, $WIN_W, $WIN_H, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0);
die "Renderer: " . SDL_GetError() unless $renderer;

# Тайлсет (с пиктограммами для кнопок)
my $tileset_tex = undef;

# Генерация тайлсета с иконками Import (стрелка вниз) и Save (дискета)
sub generate_tileset {
    print "Генерирую тайлсет с иконками...\n";
    my $surf = SDL_CreateRGBSurface(0, 512, 512, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000);
    my $fmt = $ffi->cast('opaque' => 'opaque', $surf + 24);
    my $grey = SDL_MapRGBA($fmt, 180, 180, 180, 255);
    SDL_FillRect($surf, undef, $grey);
    # Тайл 1 – стрелка вниз (Import)
    my $arrow = SDL_MapRGBA($fmt, 0, 0, 0, 255);   # чёрный
    my $white = SDL_MapRGBA($fmt, 255, 255, 255, 255);
    my $t1 = pack('iiii', 0*$TILE_SIZE, 0*$TILE_SIZE, $TILE_SIZE, $TILE_SIZE);
    my $t1_ptr = $ffi->cast('string' => 'opaque', $t1);
    SDL_FillRect($surf, $t1_ptr, $white);
    # Рисуем стрелку пикселями (очень грубо)
    my @arrow_pix = (
        "..##....",
        ".####...",
        "######..",
        "..##....",
        "..##....",
        "..##....",
        "........",
        "........"
    );
    for my $y (0..$#arrow_pix) {
        for my $x (0..7) {
            my $ch = substr($arrow_pix[$y], $x, 1);
            next unless $ch eq '#';
            my $px_rect = pack('iiii', 0+$x, 0+$y, 1, 1);
            my $px_ptr = $ffi->cast('string' => 'opaque', $px_rect);
            SDL_FillRect($surf, $px_ptr, $arrow);
        }
    }
    # Тайл 2 – дискета (Save)
    my $t2 = pack('iiii', 1*$TILE_SIZE, 0, $TILE_SIZE, $TILE_SIZE);
    my $t2_ptr = $ffi->cast('string' => 'opaque', $t2);
    SDL_FillRect($surf, $t2_ptr, $white);
    # Дискета (упрощённый квадрат с полоской)
    for my $y (1..6) {
        for my $x (1..6) {
            my $px_rect = pack('iiii', 8+$x, $y, 1, 1);
            my $px_ptr = $ffi->cast('string' => 'opaque', $px_rect);
            SDL_FillRect($surf, $px_ptr, $arrow);
        }
    }
    for my $y (2..3) {
        my $px_rect = pack('iiii', 8+2, $y, 3, 1);
        my $px_ptr = $ffi->cast('string' => 'opaque', $px_rect);
        SDL_FillRect($surf, $px_ptr, $white);   # прорезь
    }
    # Остальные тайлы – цветные
    for my $id (3..80) {
        my $col = $id % $TS_COLS;
        my $row = int($id / $TS_COLS);
        my $r = int(rand(255));
        my $g = int(rand(255));
        my $b = int(rand(255));
        my $color = SDL_MapRGBA($fmt, $r, $g, $b, 255);
        my $rect = pack('iiii', $col * $TILE_SIZE, $row * $TILE_SIZE, $TILE_SIZE, $TILE_SIZE);
        my $rect_ptr = $ffi->cast('string' => 'opaque', $rect);
        SDL_FillRect($surf, $rect_ptr, $color);
    }
    $tileset_tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    print "Тайлсет готов (1 – Import, 2 – Save).\n";
}

if (-f $TILESET_FILE) {
    my $surf = IMG_Load($TILESET_FILE);
    if ($surf) {
        $tileset_tex = SDL_CreateTextureFromSurface($renderer, $surf);
        SDL_FreeSurface($surf);
        print "Тайлсет загружен из файла.\n";
    } else {
        print "Ошибка загрузки: " . SDL_GetError() . "\n";
        generate_tileset();
    }
} else {
    print "Файл тайлсета не найден.\n";
    generate_tileset();
}

# Переменные
my $cur_tile_id = 3;
my $mouse_x = 0;
my $mouse_y = 0;
my $mouse_button = 0;
my $pal_scroll_y = 0;
my $pal_content_h = int($TOTAL_TILES / $PAL_COLS) * $PAL_TILE_H;
my $pal_max_scroll = $pal_content_h - $PAL_AREA_H;
$pal_max_scroll = 0 if $pal_max_scroll < 0;
my $pal_thumb_h = ($PAL_AREA_H / $pal_content_h) * $PAL_AREA_H;
$pal_thumb_h = 16 if $pal_thumb_h < 16;
my $pal_thumb_y = 0;
my $dragging_scroll = 0;
my $drag_start_y = 0;
my $drag_start_thumb_y = 0;

my $src_rect = malloc(16);
my $dst_rect = malloc(16);
my $event_ptr = malloc(56);

# Кнопки (крупные, с иконками)
my $btn_import_x = 8;
my $btn_import_y = 8;
my $btn_import_w = 80;
my $btn_import_h = 34;

my $btn_save_x = $btn_import_x + $btn_import_w + 12;
my $btn_save_y = $btn_import_y;
my $btn_save_w = 80;
my $btn_save_h = 34;

# Функции
sub tile_src {
    my ($id) = @_;
    return ( ($id % $TS_COLS) * $TILE_SIZE, int($id / $TS_COLS) * $TILE_SIZE );
}

sub get_palette_tile_id {
    my ($mx, $my) = @_;
    my $pal_y = $my - $TOP_BAR_H;
    return -1 if $pal_y < 0 || $pal_y >= $PAL_AREA_H;
    my $content_y = $pal_y + $pal_scroll_y;
    my $col = int($mx / $PAL_TILE_W);
    my $row = int($content_y / $PAL_TILE_H);
    return -1 if $col < 0 || $col >= $PAL_COLS || $row < 0;
    my $id = $row * $PAL_COLS + $col;
    return ($id < $TOTAL_TILES) ? $id : -1;
}

sub paint_map_cell {
    my ($screen_x, $screen_y, $tile_id) = @_;
    my $map_x = $screen_x - $PAL_PANEL_W;
    return if $map_x < 0;
    my $col = int(($map_x / $SCALE - $MAP_OFF_X) / $TILE_SIZE);
    my $row = int(($screen_y / $SCALE - $MAP_OFF_Y) / $TILE_SIZE);
    if ($row >= 0 && $row < $MAP_ROWS && $col >= 0 && $col < $MAP_COLS) {
        $map[$row][$col] = $tile_id;
    }
}

sub save_map {
    open(my $fh, '>', "../assets/map/map01.txt") or die;
    for my $row (@map) { print $fh join(' ', @$row) . "\n"; }
    close $fh;
    print "Карта сохранена.\n";
}

sub import_tileset {
    my $surf = IMG_Load($TILESET_FILE);
    if ($surf) {
        $tileset_tex = SDL_CreateTextureFromSurface($renderer, $surf);
        SDL_FreeSurface($surf);
        print "Тайлсет импортирован.\n";
    } else { print "Ошибка импорта: " . SDL_GetError() . "\n"; }
}

print "Редактор запущен.\n";
print "Кнопки: Import (стрелка вниз) и Save (дискета).\n";
print "ЛКМ рисует, ПКМ стирает (можно зажать и вести).\n";

my $running = 1;
while ($running) {
    my $event_str = "\0" x 56;
    my $event_str_ptr = $ffi->cast('string' => 'opaque', $event_str);

    while (SDL_PollEvent($event_ptr)) {
        memcpy($event_str_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));

        if ($type == 0x100) { $running = 0; }
        elsif ($type == 0x400) {   # движение мыши
            $mouse_x = unpack('V', substr($event_str, 16, 4));
            $mouse_y = unpack('V', substr($event_str, 20, 4));
            # Непрерывное рисование
            if (($mouse_button == 1 || $mouse_button == 3) && $mouse_x >= $PAL_PANEL_W) {
                my $tid = ($mouse_button == 1) ? $cur_tile_id : 0;
                paint_map_cell($mouse_x, $mouse_y, $tid);
            }
            # Перетаскивание ползунка
            if ($dragging_scroll) {
                my $delta = $mouse_y - $drag_start_y;
                my $max_thumb_y = $PAL_AREA_H - $pal_thumb_h;
                my $new_thumb_y = $drag_start_thumb_y + $delta;
                $new_thumb_y = 0 if $new_thumb_y < 0;
                $new_thumb_y = $max_thumb_y if $new_thumb_y > $max_thumb_y;
                $pal_scroll_y = ($max_thumb_y > 0) ? int(($new_thumb_y / $max_thumb_y) * $pal_max_scroll) : 0;
                $pal_thumb_y = $new_thumb_y;
            }
        }
        elsif ($type == 0x401) {   # нажатие кнопки мыши
            my $btn = unpack('C', substr($event_str, 16, 1));
            $mouse_button = $btn;
            my $cx = unpack('V', substr($event_str, 20, 4));
            my $cy = unpack('V', substr($event_str, 24, 4));
            $mouse_x = $cx; $mouse_y = $cy;

            # Кнопка Import
            if ($cx >= $btn_import_x && $cx <= $btn_import_x + $btn_import_w &&
                $cy >= $btn_import_y && $cy <= $btn_import_y + $btn_import_h) {
                print "Нажата Import\n";
                import_tileset();
            }
            # Кнопка Save
            elsif ($cx >= $btn_save_x && $cx <= $btn_save_x + $btn_save_w &&
                   $cy >= $btn_save_y && $cy <= $btn_save_y + $btn_save_h) {
                print "Нажата Save\n";
                save_map();
            }
            # Полоса прокрутки
            elsif ($cx >= $PAL_WIDTH && $cx <= $PAL_PANEL_W && $cy >= $TOP_BAR_H && $cy <= $TOP_BAR_H + $PAL_AREA_H) {
                my $ly = $cy - $TOP_BAR_H;
                if ($ly < $pal_thumb_y) { $pal_scroll_y -= $PAL_AREA_H; }
                elsif ($ly > $pal_thumb_y + $pal_thumb_h) { $pal_scroll_y += $PAL_AREA_H; }
                else {
                    $dragging_scroll = 1;
                    $drag_start_thumb_y = $pal_thumb_y;
                    $drag_start_y = $ly;
                }
                $pal_scroll_y = 0 if $pal_scroll_y < 0;
                $pal_scroll_y = $pal_max_scroll if $pal_scroll_y > $pal_max_scroll;
                my $max_thumb_y = $PAL_AREA_H - $pal_thumb_h;
                $pal_thumb_y = ($pal_max_scroll > 0) ? int(($pal_scroll_y / $pal_max_scroll) * $max_thumb_y) : 0;
            }
            # Палитра
            elsif ($cx < $PAL_WIDTH && $cy >= $TOP_BAR_H) {
                my $id = get_palette_tile_id($cx, $cy);
                if ($id >= 0) { $cur_tile_id = $id; print "Выбран тайл: $id\n"; }
            }
            # Карта (первый клик)
            elsif ($cx >= $PAL_PANEL_W) {
                my $tid = ($btn == 1) ? $cur_tile_id : (($btn == 3) ? 0 : -1);
                if ($tid >= 0) { paint_map_cell($cx, $cy, $tid); }
            }
        }
        elsif ($type == 0x402) {   # отпускание мыши
            $dragging_scroll = 0;
            $mouse_button = 0;
        }
        elsif ($type == 0x700) {   # колёсико мыши
            my $wy = unpack('l', substr($event_str, 20, 4));
            $pal_scroll_y -= $wy * 24;
            $pal_scroll_y = 0 if $pal_scroll_y < 0;
            $pal_scroll_y = $pal_max_scroll if $pal_scroll_y > $pal_max_scroll;
            my $max_thumb_y = $PAL_AREA_H - $pal_thumb_h;
            $pal_thumb_y = ($pal_max_scroll > 0) ? int(($pal_scroll_y / $pal_max_scroll) * $max_thumb_y) : 0;
        }
        elsif ($type == 0x300) {   # клавиша
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 27) { $running = 0; }
            elsif ($key == 115) { save_map(); }        # S
            elsif ($key == 111) { import_tileset(); }  # O
        }
    }

    # ---------- РЕНДЕР ----------
    SDL_SetRenderDrawColor($renderer, 40, 40, 40, 255);
    SDL_RenderClear($renderer);

    # Верхняя панель с кнопками
    my $top_bar = pack('iiii', 0, 0, $PAL_PANEL_W, $TOP_BAR_H);
    my $top_bar_ptr = $ffi->cast('string' => 'opaque', $top_bar);
    SDL_SetRenderDrawColor($renderer, 60, 60, 60, 255);
    SDL_RenderFillRect($renderer, $top_bar_ptr);

    # Кнопка Import (синяя, с иконкой – тайл 1)
    my $btn_import_rect = pack('iiii', $btn_import_x, $btn_import_y, $btn_import_w, $btn_import_h);
    my $btn_import_ptr = $ffi->cast('string' => 'opaque', $btn_import_rect);
    SDL_SetRenderDrawColor($renderer, 70, 70, 220, 255);
    SDL_RenderFillRect($renderer, $btn_import_ptr);
    SDL_SetRenderDrawColor($renderer, 255, 255, 0, 255);
    SDL_RenderDrawRect($renderer, $btn_import_ptr);
    # Иконка Import (тайл 1)
    if ($tileset_tex) {
        my ($sx, $sy) = tile_src(1);
        my $icon_src = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
        my $icon_src_ptr = $ffi->cast('string' => 'opaque', $icon_src);
        my $icon_dst = pack('iiii', $btn_import_x+4, $btn_import_y+4, $TILE_SIZE*$SCALE, $TILE_SIZE*$SCALE);
        my $icon_dst_ptr = $ffi->cast('string' => 'opaque', $icon_dst);
        memcpy($src_rect, $icon_src_ptr, 16);
        memcpy($dst_rect, $icon_dst_ptr, 16);
        SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
    }

    # Кнопка Save (красная, с иконкой – тайл 2)
    my $btn_save_rect = pack('iiii', $btn_save_x, $btn_save_y, $btn_save_w, $btn_save_h);
    my $btn_save_ptr = $ffi->cast('string' => 'opaque', $btn_save_rect);
    SDL_SetRenderDrawColor($renderer, 220, 70, 70, 255);
    SDL_RenderFillRect($renderer, $btn_save_ptr);
    SDL_SetRenderDrawColor($renderer, 255, 255, 0, 255);
    SDL_RenderDrawRect($renderer, $btn_save_ptr);
    if ($tileset_tex) {
        my ($sx, $sy) = tile_src(2);
        my $icon_src = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
        my $icon_src_ptr = $ffi->cast('string' => 'opaque', $icon_src);
        my $icon_dst = pack('iiii', $btn_save_x+4, $btn_save_y+4, $TILE_SIZE*$SCALE, $TILE_SIZE*$SCALE);
        my $icon_dst_ptr = $ffi->cast('string' => 'opaque', $icon_dst);
        memcpy($src_rect, $icon_src_ptr, 16);
        memcpy($dst_rect, $icon_dst_ptr, 16);
        SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
    }

    # Палитра
    my $pal_y_off = $TOP_BAR_H;
    my $pal_bg = pack('iiii', 0, $pal_y_off, $PAL_WIDTH, $PAL_AREA_H);
    my $pal_bg_ptr = $ffi->cast('string' => 'opaque', $pal_bg);
    SDL_SetRenderDrawColor($renderer, 50, 50, 50, 255);
    SDL_RenderFillRect($renderer, $pal_bg_ptr);

    my $start_row = int($pal_scroll_y / $PAL_TILE_H);
    my $end_row   = int(($pal_scroll_y + $PAL_AREA_H - 1) / $PAL_TILE_H);
    for my $row ($start_row .. $end_row) {
        for my $col (0 .. $PAL_COLS-1) {
            my $id = $row * $PAL_COLS + $col;
            next if $id >= $TOTAL_TILES;
            my ($sx, $sy) = tile_src($id);
            my $dx = $col * $PAL_TILE_W;
            my $dy = $pal_y_off + $row * $PAL_TILE_H - $pal_scroll_y;

            my $packed_src = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
            my $src_ptr = $ffi->cast('string' => 'opaque', $packed_src);
            memcpy($src_rect, $src_ptr, 16);

            my $packed_dst = pack('iiii', $dx, $dy, $PAL_TILE_W, $PAL_TILE_H);
            my $dst_ptr = $ffi->cast('string' => 'opaque', $packed_dst);
            memcpy($dst_rect, $dst_ptr, 16);

            SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);

            if ($id == $cur_tile_id) {
                SDL_SetRenderDrawColor($renderer, 255, 255, 0, 255);
                SDL_RenderDrawRect($renderer, $dst_ptr);
            }
        }
    }

    # Полоса прокрутки
    my $scroll_track = pack('iiii', $PAL_WIDTH, $pal_y_off, $SCROLLBAR_W, $PAL_AREA_H);
    my $track_ptr = $ffi->cast('string' => 'opaque', $scroll_track);
    SDL_SetRenderDrawColor($renderer, 100, 100, 100, 255);
    SDL_RenderFillRect($renderer, $track_ptr);

    my $thumb = pack('iiii', $PAL_WIDTH, $pal_y_off + $pal_thumb_y, $SCROLLBAR_W, $pal_thumb_h);
    my $thumb_ptr = $ffi->cast('string' => 'opaque', $thumb);
    SDL_SetRenderDrawColor($renderer, 200, 200, 200, 255);
    SDL_RenderFillRect($renderer, $thumb_ptr);

    # Карта
    my $map_bg = pack('iiii', $PAL_PANEL_W, 0, $MAP_W, $MAP_H);
    my $map_bg_ptr = $ffi->cast('string' => 'opaque', $map_bg);
    SDL_SetRenderDrawColor($renderer, 25, 25, 70, 255);
    SDL_RenderFillRect($renderer, $map_bg_ptr);

    for my $row (0..$MAP_ROWS-1) {
        for my $col (0..$MAP_COLS-1) {
            my $id = $map[$row][$col];
            next unless $id > 0;
            my ($sx, $sy) = tile_src($id);
            my $dx = $PAL_PANEL_W + ($MAP_OFF_X + $col * $TILE_SIZE) * $SCALE;
            my $dy = ($MAP_OFF_Y + $row * $TILE_SIZE) * $SCALE;
            my $dw = $TILE_SIZE * $SCALE;
            my $dh = $TILE_SIZE * $SCALE;

            my $packed_src = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
            my $src_ptr = $ffi->cast('string' => 'opaque', $packed_src);
            memcpy($src_rect, $src_ptr, 16);

            my $packed_dst = pack('iiii', $dx, $dy, $dw, $dh);
            my $dst_ptr = $ffi->cast('string' => 'opaque', $packed_dst);
            memcpy($dst_rect, $dst_ptr, 16);

            SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
        }
    }

    # Сетка карты
    SDL_SetRenderDrawColor($renderer, 80, 80, 80, 100);
    for my $row (0..$MAP_ROWS) {
        my $y = ($MAP_OFF_Y + $row * $TILE_SIZE) * $SCALE;
        SDL_RenderDrawLine($renderer, $PAL_PANEL_W + $MAP_OFF_X * $SCALE, $y,
                           $PAL_PANEL_W + ($MAP_OFF_X + $MAP_COLS * $TILE_SIZE) * $SCALE, $y);
    }
    for my $col (0..$MAP_COLS) {
        my $x = $PAL_PANEL_W + ($MAP_OFF_X + $col * $TILE_SIZE) * $SCALE;
        SDL_RenderDrawLine($renderer, $x, $MAP_OFF_Y * $SCALE,
                           $x, ($MAP_OFF_Y + $MAP_ROWS * $TILE_SIZE) * $SCALE);
    }

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

free($src_rect);
free($dst_rect);
free($event_ptr);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();
print "Редактор закрыт.\n";