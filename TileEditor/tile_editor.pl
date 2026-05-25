use strict;
use warnings;
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

BEGIN { $ENV{PATH} .= ';C:\Strawberry\perl\vendor\lib\SDL2'; }

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

# Функции SDL
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
SDL_SetHint("SDL_HINT_RENDER_SCALE_QUALITY", "0");

# ---------- НАСТРОЙКИ ----------
my $SCALE        = 3;
my $TILE_SIZE    = 8;
my $MAP_COLS     = 31;
my $MAP_ROWS     = 20;
my $MAP_OFF_X    = 4;
my $MAP_OFF_Y    = 4;
my $MAP_W        = ($MAP_OFF_X + $MAP_COLS * $TILE_SIZE) * $SCALE;
my $MAP_H        = ($MAP_OFF_Y + $MAP_ROWS * $TILE_SIZE) * $SCALE;

my $PAL_COLS     = 16;
my $PAL_TILE_W   = $TILE_SIZE * $SCALE;
my $PAL_TILE_H   = $TILE_SIZE * $SCALE;
my $PAL_WIDTH    = $PAL_COLS * $PAL_TILE_W;
my $PAL_AREA_H   = 600;
my $SCROLLBAR_W  = 16;
my $PAL_PANEL_W  = $PAL_WIDTH + $SCROLLBAR_W;

my $WIN_W = $PAL_PANEL_W + $MAP_W;
my $WIN_H = $MAP_H > $PAL_AREA_H ? $MAP_H : $PAL_AREA_H;
$WIN_H = 600 if $WIN_H < 600;

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

# Тайлсет (текстура)
my $tileset_tex = undef;

sub generate_tileset {
    print "Генерирую тестовый тайлсет 512x512...\n";
    my $surf = SDL_CreateRGBSurface(0, 512, 512, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000);
    my $fmt = $ffi->cast('opaque' => 'opaque', $surf + 24);
    my $grey = SDL_MapRGBA($fmt, 180, 180, 180, 255);
    SDL_FillRect($surf, undef, $grey);
    for my $id (1..50) {
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
    print "Тестовый тайлсет готов.\n";
}

if (-f $TILESET_FILE) {
    my $surf = IMG_Load($TILESET_FILE);
    if ($surf) {
        $tileset_tex = SDL_CreateTextureFromSurface($renderer, $surf);
        SDL_FreeSurface($surf);
        print "Тайлсет загружен из файла.\n";
    } else {
        print "Ошибка загрузки файла: " . SDL_GetError() . "\n";
        generate_tileset();
    }
} else {
    print "Файл тайлсета не найден.\n";
    generate_tileset();
}

# Переменные редактора
my $cur_tile_id   = 1;
my $mouse_x       = 0;
my $mouse_y       = 0;
my $mouse_button  = 0;
my $pal_scroll_y  = 0;
my $pal_content_h = int($TOTAL_TILES / $PAL_COLS) * $PAL_TILE_H;
my $pal_max_scroll = $pal_content_h - $PAL_AREA_H;
$pal_max_scroll = 0 if $pal_max_scroll < 0;
my $pal_thumb_h = ($PAL_AREA_H / $pal_content_h) * $PAL_AREA_H;
$pal_thumb_h = 12 if $pal_thumb_h < 12;
my $pal_thumb_y = 0;
my $dragging_scroll = 0;
my $drag_start_y = 0;
my $drag_start_thumb_y = 0;

# Прямоугольники
my $src_rect = malloc(16);
my $dst_rect = malloc(16);
my $event_ptr = malloc(56);
die "malloc event failed" unless $event_ptr;

sub tile_src {
    my ($id) = @_;
    return ( ($id % $TS_COLS) * $TILE_SIZE, int($id / $TS_COLS) * $TILE_SIZE );
}

sub get_palette_tile_id {
    my ($mx, $my) = @_;
    my $content_y = $my + $pal_scroll_y;
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
    open(my $fh, '>', "../assets/map/map01.txt") or die "Cannot save: $!";
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
    } else {
        print "Ошибка импорта: " . SDL_GetError() . "\n";
    }
}

print "Редактор готов. Слева палитра, справа карта.\n";
print "ЛКМ – рисовать, ПКМ – стереть, Скролл – выбор тайла.\n";
print "S – сохранить, O – импорт tileset.png, Esc – выход.\n";

my $running = 1;
while ($running) {
    my $event_str = "\0" x 56;
    my $event_str_ptr = $ffi->cast('string' => 'opaque', $event_str);

    while (SDL_PollEvent($event_ptr)) {
        memcpy($event_str_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));

        if ($type == 0x100) { $running = 0; }
        elsif ($type == 0x400) {                           # движение мыши
            $mouse_x = unpack('V', substr($event_str, 16, 4));
            $mouse_y = unpack('V', substr($event_str, 20, 4));
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
        elsif ($type == 0x401) {                           # кнопка мыши нажата
            my $btn = unpack('C', substr($event_str, 16, 1));
            $mouse_button = $btn;
            my $cx = unpack('V', substr($event_str, 20, 4));
            my $cy = unpack('V', substr($event_str, 24, 4));

            if ($cx >= $PAL_WIDTH && $cx <= $PAL_PANEL_W && $cy >= 0 && $cy <= $PAL_AREA_H) {
                # Клик по полосе прокрутки
                if ($cy < $pal_thumb_y) {
                    $pal_scroll_y -= $PAL_AREA_H;
                } elsif ($cy > $pal_thumb_y + $pal_thumb_h) {
                    $pal_scroll_y += $PAL_AREA_H;
                } else {
                    $dragging_scroll = 1;
                    $drag_start_thumb_y = $pal_thumb_y;
                    $drag_start_y = $cy;
                }
                $pal_scroll_y = 0 if $pal_scroll_y < 0;
                $pal_scroll_y = $pal_max_scroll if $pal_scroll_y > $pal_max_scroll;
                my $max_thumb_y = $PAL_AREA_H - $pal_thumb_h;
                $pal_thumb_y = ($pal_max_scroll > 0) ? int(($pal_scroll_y / $pal_max_scroll) * $max_thumb_y) : 0;
            }
            elsif ($cx < $PAL_WIDTH) {
                my $id = get_palette_tile_id($cx, $cy);
                if ($id >= 0) { $cur_tile_id = $id; print "Выбран тайл: $id\n"; }
            }
            else {
                if ($btn == 1) { paint_map_cell($cx, $cy, $cur_tile_id); }
                elsif ($btn == 3) { paint_map_cell($cx, $cy, 0); }
            }
        }
        elsif ($type == 0x402) { $dragging_scroll = 0; $mouse_button = 0; }
        elsif ($type == 0x700) {                           # колёсико мыши
            my $wy = unpack('l', substr($event_str, 20, 4));
            $pal_scroll_y -= $wy * 20;
            $pal_scroll_y = 0 if $pal_scroll_y < 0;
            $pal_scroll_y = $pal_max_scroll if $pal_scroll_y > $pal_max_scroll;
            my $max_thumb_y = $PAL_AREA_H - $pal_thumb_h;
            $pal_thumb_y = ($pal_max_scroll > 0) ? int(($pal_scroll_y / $pal_max_scroll) * $max_thumb_y) : 0;
        }
        elsif ($type == 0x300) {                           # клавиша
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 27) { $running = 0; }
            elsif ($key == 115) { save_map(); }            # S
            elsif ($key == 111) { import_tileset(); }      # O
        }
    }

    # Непрерывное рисование при зажатой кнопке
    if (($mouse_button == 1 || $mouse_button == 3) && $mouse_x >= $PAL_PANEL_W) {
        my $tid = ($mouse_button == 1) ? $cur_tile_id : 0;
        paint_map_cell($mouse_x, $mouse_y, $tid);
    }

    # ---------- РЕНДЕР ----------
    SDL_SetRenderDrawColor($renderer, 30, 30, 30, 255);
    SDL_RenderClear($renderer);

    # Фон палитры
    my $pal_bg = pack('iiii', 0, 0, $PAL_WIDTH, $PAL_AREA_H);
    my $pal_bg_ptr = $ffi->cast('string' => 'opaque', $pal_bg);
    SDL_SetRenderDrawColor($renderer, 50, 50, 50, 255);
    SDL_RenderFillRect($renderer, $pal_bg_ptr);

    # Тайлы палитры
    my $start_row = int($pal_scroll_y / $PAL_TILE_H);
    my $end_row   = int(($pal_scroll_y + $PAL_AREA_H - 1) / $PAL_TILE_H);
    for my $row ($start_row .. $end_row) {
        for my $col (0 .. $PAL_COLS-1) {
            my $id = $row * $PAL_COLS + $col;
            next if $id >= $TOTAL_TILES;
            my ($sx, $sy) = tile_src($id);
            my $dx = $col * $PAL_TILE_W;
            my $dy = $row * $PAL_TILE_H - $pal_scroll_y;

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

    # Полоса прокрутки палитры
    my $scroll_track = pack('iiii', $PAL_WIDTH, 0, $SCROLLBAR_W, $PAL_AREA_H);
    my $track_ptr = $ffi->cast('string' => 'opaque', $scroll_track);
    SDL_SetRenderDrawColor($renderer, 100, 100, 100, 255);
    SDL_RenderFillRect($renderer, $track_ptr);

    my $thumb = pack('iiii', $PAL_WIDTH, $pal_thumb_y, $SCROLLBAR_W, $pal_thumb_h);
    my $thumb_ptr = $ffi->cast('string' => 'opaque', $thumb);
    SDL_SetRenderDrawColor($renderer, 200, 200, 200, 255);
    SDL_RenderFillRect($renderer, $thumb_ptr);

    # Фон карты
    SDL_SetRenderDrawColor($renderer, 25, 25, 70, 255);
    my $map_bg = pack('iiii', $PAL_PANEL_W, 0, $MAP_W, $MAP_H);
    my $map_bg_ptr = $ffi->cast('string' => 'opaque', $map_bg);
    SDL_RenderFillRect($renderer, $map_bg_ptr);

    # Тайлы карты
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