use strict;
use warnings;
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

BEGIN { $ENV{PATH} .= ';D:\perl5\share\SDL2\lib'; }

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

$ffi->attach( SDL_Init               => ['uint']                     => 'int' );
$ffi->attach( SDL_GetError           => []                           => 'string' );
$ffi->attach( SDL_SetHint            => ['string', 'string']         => 'int' );
$ffi->attach( SDL_CreateWindow       => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer     => ['opaque','int','uint']      => 'opaque' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear        => ['opaque']                   => 'int' );
$ffi->attach( SDL_RenderCopy         => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent      => ['opaque']                   => 'void' );
$ffi->attach( SDL_PollEvent          => ['opaque']                   => 'int' );
$ffi->attach( SDL_Delay              => ['uint']                     => 'void' );
$ffi->attach( SDL_DestroyRenderer    => ['opaque']                   => 'void' );
$ffi->attach( SDL_DestroyWindow      => ['opaque']                   => 'void' );
$ffi->attach( SDL_Quit               => []                           => 'void' );
$ffi->attach( SDL_GetKeyboardState   => ['opaque']                   => 'opaque' );
$ffi->attach( SDL_FreeSurface        => ['opaque']                   => 'void' );

$ffi->attach( IMG_Load                => ['string']                  => 'opaque' );
$ffi->attach( IMG_Init                => ['int']                     => 'int' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque']    => 'opaque' );
$ffi->attach( SDL_RenderCopyEx        => ['opaque','opaque','opaque','opaque','double','opaque','int'] => 'int' );

# Инициализация
die "SDL_Init failed: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init failed"                unless IMG_Init(2) & 2;   # PNG

SDL_SetHint("SDL_HINT_RENDER_SCALE_QUALITY", "0");  # nearest-фильтр

my $scale   = 3;
my $window_w = 256 * $scale;       # 768
my $window_h = 224 * $scale;       # 672
my $window   = SDL_CreateWindow("Crimson Dragon 3 (NTSC)", 100, 100, $window_w, $window_h, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0);
die "Renderer failed" unless $renderer;

my $event_ptr = malloc(56);
die "malloc event failed" unless $event_ptr;

# ---------------------- Тайлы и карта ----------------------
my $tile_size = 8;
my $map_cols  = 31;   # 248 / 8
my $map_rows  = 20;   # 160 / 8

# Загружаем тайлсет (вертикальный)
my $tileset_surface = IMG_Load("assets/map/tileset.png");
die "No tileset: " . SDL_GetError() unless $tileset_surface;
my $tileset_tex = SDL_CreateTextureFromSurface($renderer, $tileset_surface);
SDL_FreeSurface($tileset_surface);

# Загружаем карту из текстового файла
my @map;
open(my $fh, '<', "assets/map/map01.txt") or die "Map file missing: $!";
while (<$fh>) {
    chomp;
    s/^\s+//; s/\s+$//;
    next if $_ eq '';
    my @row = split /\s+/, $_;
    die "Wrong number of columns in map line" if @row != $map_cols;
    push @map, \@row;
}
close $fh;
die "Map must have $map_rows rows" if @map != $map_rows;

# Логические отступы карты (как в NES)
my $map_x = 4;
my $map_y = 4;

# Прямоугольники для тайлов (используем в цикле)
my $src_tile = malloc(16);
my $dst_tile = malloc(16);

# ---------------------- Спрайты Билли ----------------------
my $base = "assets/sprites/Billy";

my $billy_surf = IMG_Load("$base/Billy.png") or die "Billy.png: " . SDL_GetError();
my $billy_tex  = SDL_CreateTextureFromSurface($renderer, $billy_surf);
SDL_FreeSurface($billy_surf);

my $attack_surf = IMG_Load("$base/Attack_A.png") or die "Attack_A.png: " . SDL_GetError();
my $attack_tex  = SDL_CreateTextureFromSurface($renderer, $attack_surf);
SDL_FreeSurface($attack_surf);

my $frame_w       = 36;
my $frame_h       = 40;
my $billy_frames  = 4;
my $attack_frames = 3;
my $attack_dur    = 6;

# ---------------------- Персонаж ----------------------
my %player = (
    x          => 100,
    y          => 100,
    frame      => 3,      # стойка
    anim_timer => 0,
    direction  => 1,
    speed      => 1.5,
    moving     => 0,
    is_attacking => 0,
    attack_frame => 0,
    attack_timer => 0,
);

# Прямоугольники для спрайта персонажа
my $src_rect = malloc(16);
my $dst_rect = malloc(16);

# Буфер клавиатуры
my $keys_buf = malloc(512);

my $running = 1;
print "NTSC mode (256x224 x3) started\n";
print "Arrows/WASD move, A/J attack, Esc close\n\n";

my $event_str = "\0" x 56;
my $event_str_ptr = $ffi->cast('string' => 'opaque', $event_str);

# ---------------------- Функция коллизии с тайлами ----------------------
sub tile_collision {
    my ($x, $y, $w, $h) = @_;
    my $left   = int($x / $tile_size);
    my $right  = int(($x + $w - 1) / $tile_size);
    my $top    = int($y / $tile_size);
    my $bottom = int(($y + $h - 1) / $tile_size);

    for my $row ($top..$bottom) {
        for my $col ($left..$right) {
            # За границей карты – стена
            return 1 if $row < 0 || $row >= $map_rows || $col < 0 || $col >= $map_cols;
            # Все тайлы проходимы (строка ниже закомментирована)
            # return 1 if $map[$row][$col] != 0;
        }
    }
    return 0;
}

# ---------------------- Основной цикл ----------------------
while ($running) {
    # ----- События -----
    while (SDL_PollEvent($event_ptr)) {
        memcpy($event_str_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));
        if ($type == 0x100) { $running = 0; }
        elsif ($type == 0x300) {
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 27) { $running = 0; }   # Esc
            if (($key == 97 || $key == 106) && !$player{is_attacking}) {
                $player{is_attacking} = 1;
                $player{attack_frame} = 0;
                $player{attack_timer} = 0;
            }
        }
    }

    # ----- Движение -----
    if (!$player{is_attacking}) {
        my $keys_ptr = SDL_GetKeyboardState(undef);
        my $keys_str = "\0" x 512;
        my $keys_str_ptr = $ffi->cast('string' => 'opaque', $keys_str);
        memcpy($keys_str_ptr, $keys_ptr, 512);

        my $left  = vec($keys_str, 0x50, 8) || vec($keys_str, 0x04, 8);
        my $right = vec($keys_str, 0x4F, 8) || vec($keys_str, 0x07, 8);
        my $up    = vec($keys_str, 0x52, 8) || vec($keys_str, 0x1A, 8);
        my $down  = vec($keys_str, 0x51, 8) || vec($keys_str, 0x16, 8);

        $player{moving} = 0;
        my $dx = 0; my $dy = 0;
        $dx -= 1 if $left;
        $dx += 1 if $right;
        $dy -= 1 if $up;
        $dy += 1 if $down;

        if ($dx || $dy) {
            $player{moving} = 1;
            # Раздельная проверка по осям
            my $new_x = $player{x} + $dx * $player{speed};
            my $new_y = $player{y} + $dy * $player{speed} * 0.7;

            # Хитбокс персонажа (немного уменьшаем)
            my $hb_w = 24;
            my $hb_h = 36;
            my $hb_x = $new_x + 6;   # отступы от левого края спрайта
            my $hb_y = $new_y + 2;

            if (!tile_collision($hb_x, $player{y} + 2, $hb_w, $hb_h)) {
                $player{x} = $new_x;
            }
            if (!tile_collision($player{x} + 6, $hb_y, $hb_w, $hb_h)) {
                $player{y} = $new_y;
            }
            $player{direction} = $dx if $dx != 0;
        }
    }

    # ----- Анимация -----
    if ($player{is_attacking}) {
        $player{attack_timer}++;
        if ($player{attack_timer} >= $attack_dur) {
            $player{attack_timer} = 0;
            $player{attack_frame}++;
            if ($player{attack_frame} >= $attack_frames) {
                $player{is_attacking} = 0;
                $player{attack_frame} = 0;
                $player{frame} = 3;
            }
        }
    } else {
        if ($player{moving}) {
            if (++$player{anim_timer} >= 5) {
                $player{anim_timer} = 0;
                $player{frame} = ($player{frame} + 1) % 3;
            }
        } else {
            $player{frame} = 3;
        }
    }

    # Ограничение в пределах карты (на всякий случай)
    $player{x} = 0 if $player{x} < 0;
    $player{x} = 248 - 36 if $player{x} > 212;
    $player{y} = 0 if $player{y} < 0;
    $player{y} = 160 - 40 if $player{y} > 120;

    # ----- Рендер -----
    SDL_SetRenderDrawColor($renderer, 0, 0, 0, 255);
    SDL_RenderClear($renderer);

    # Рисуем тайлы карты
    my $ts_cols = 64;   # ← ВАЖНО: ширина тайлсета в тайлах (как в редакторе)
    for my $row (0..$map_rows-1) {
        for my $col (0..$map_cols-1) {
            my $id = $map[$row][$col];
            next if $id <= 0;   # пустые не рисуем

            # Правильные координаты в сетке 64x64
            my $src_x = ($id % $ts_cols) * $tile_size;
            my $src_y = int($id / $ts_cols) * $tile_size;

            my $packed_src = pack('iiii', $src_x, $src_y, $tile_size, $tile_size);
            my $src_ptr = $ffi->cast('string' => 'opaque', $packed_src);
            memcpy($src_tile, $src_ptr, 16);

            my $screen_x = ($map_x + $col * $tile_size) * $scale;
            my $screen_y = ($map_y + $row * $tile_size) * $scale;
            my $packed_dst = pack('iiii', $screen_x, $screen_y, $tile_size * $scale, $tile_size * $scale);
            my $dst_ptr = $ffi->cast('string' => 'opaque', $packed_dst);
            memcpy($dst_tile, $dst_ptr, 16);

            SDL_RenderCopy($renderer, $tileset_tex, $src_tile, $dst_tile);
        }
    }

    # Рисуем персонажа
    my ($cur_tex, $cur_fw, $cur_fh, $frame_idx);
    if ($player{is_attacking}) {
        $cur_tex = $attack_tex;
        $cur_fw  = $frame_w;
        $cur_fh  = $frame_h;
        $frame_idx = $player{attack_frame};
    } else {
        $cur_tex = $billy_tex;
        $cur_fw  = $frame_w;
        $cur_fh  = $frame_h;
        $frame_idx = $player{frame};
    }

    my $src_packed = pack('iiii', $frame_idx * $cur_fw, 0, $cur_fw, $cur_fh);
    my $src_ptr2 = $ffi->cast('string' => 'opaque', $src_packed);
    memcpy($src_rect, $src_ptr2, 16);

    my $screen_x = ($map_x + $player{x}) * $scale;
    my $screen_y = ($map_y + $player{y}) * $scale;
    my $dst_packed = pack('iiii', $screen_x, $screen_y, $cur_fw * $scale, $cur_fh * $scale);
    my $dst_ptr2 = $ffi->cast('string' => 'opaque', $dst_packed);
    memcpy($dst_rect, $dst_ptr2, 16);

    my $flip = ($player{direction} < 0) ? 1 : 0;
    SDL_RenderCopyEx($renderer, $cur_tex, $src_rect, $dst_rect, 0, undef, $flip);

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# Очистка
free($src_tile);
free($dst_tile);
free($src_rect);
free($dst_rect);
free($event_ptr);
free($keys_buf);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();
print "Game closed.\n";