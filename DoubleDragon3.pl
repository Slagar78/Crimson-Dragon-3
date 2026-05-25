use strict;
use warnings;
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

BEGIN { $ENV{PATH} .= ';D:\perl5\share\SDL2\lib'; }

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

# Функции SDL
$ffi->attach( SDL_Init               => ['uint']                     => 'int' );
$ffi->attach( SDL_GetError           => []                           => 'string' );
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

# SDL_image
$ffi->attach( IMG_Load                => ['string']                  => 'opaque' );
$ffi->attach( IMG_Init                => ['int']                     => 'int' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque']    => 'opaque' );
$ffi->attach( SDL_RenderCopyEx        => ['opaque','opaque','opaque','opaque','double','opaque','int'] => 'int' );

# Инициализация
die "SDL_Init failed: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init failed"                unless IMG_Init(2) & 2;   # PNG

# Окно NES-разрешения
my $window_w = 256;
my $window_h = 224;
my $window   = SDL_CreateWindow("Crimson Dragon 3", 100, 100, $window_w, $window_h, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0);
die "Renderer failed" unless $renderer;

# Память для событий
my $event_ptr = malloc(56);
die "malloc event failed" unless $event_ptr;

# ---------------------- Загрузка карты ----------------------
my $map_surface = IMG_Load("assets/map/map01.png");
die "Не удалось загрузить карту: " . SDL_GetError() unless $map_surface;

my $map_w = 248;
my $map_h = 160;
my $map_texture = SDL_CreateTextureFromSurface($renderer, $map_surface);
SDL_FreeSurface($map_surface);

# Положение карты: центрируем с учётом 4 пикселей сверху и слева
my $map_x = int(($window_w - $map_w) / 2);  # 4
my $map_y = 4;                              # 4 сверху, остальное снизу (60)

# Прямоугольник для карты
my $map_rect = malloc(16);
{
    my $packed = pack('iiii', $map_x, $map_y, $map_w, $map_h);
    my $ptr = $ffi->cast('string' => 'opaque', $packed);
    memcpy($map_rect, $ptr, 16);
}

# ---------------------- Загрузка спрайтов ----------------------
my $base = "assets/sprites/Billy";

my $billy_surface = IMG_Load("$base/Billy.png");
die "Не удалось загрузить Billy.png: " . SDL_GetError() unless $billy_surface;
my $billy_texture = SDL_CreateTextureFromSurface($renderer, $billy_surface);
SDL_FreeSurface($billy_surface);
my $billy_fw = 36;
my $billy_fh = 40;
my $billy_frames = 4;

my $attack_surface = IMG_Load("$base/Attack_A.png");
die "Не удалось загрузить Attack_A.png: " . SDL_GetError() unless $attack_surface;
my $attack_texture = SDL_CreateTextureFromSurface($renderer, $attack_surface);
SDL_FreeSurface($attack_surface);
my $attack_fw = 36;
my $attack_fh = 40;
my $attack_frames = 3;
my $attack_frame_duration = 6;

# Персонаж (координаты в пикселях карты)
my %player = (
    x          => 100,       # начальная позиция на карте
    y          => 100,
    frame      => 3,          # стоячий кадр
    anim_timer => 0,
    direction  => 1,
    speed      => 1.5,        # медленнее для маленького экрана
    moving     => 0,
    is_attacking => 0,
    attack_frame => 0,
    attack_timer => 0,
);

# Прямоугольники для спрайтов
my $src_rect = malloc(16);
my $dst_rect = malloc(16);

# Буфер клавиатуры
my $keys_buf = malloc(512);
die "malloc keys failed" unless $keys_buf;

my $running = 1;
print "Crimson Dragon 3 запущена\n";
print "Управление: стрелки или WASD\n";
print "Атака: клавиша A (или J)\n";
print "Закрытие: крестик или Esc\n\n";

my $event_str = "\0" x 56;
my $event_str_ptr = $ffi->cast('string' => 'opaque', $event_str);

while ($running) {
    # ------------------- Обработка событий --------------------
    while (SDL_PollEvent($event_ptr)) {
        memcpy($event_str_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));

        if ($type == 0x100) {          # SDL_QUIT
            $running = 0;
        }
        elsif ($type == 0x300) {       # SDL_KEYDOWN
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 27) {          # Esc
                $running = 0;
            }
            if (($key == 97 || $key == 106) && !$player{is_attacking}) {
                $player{is_attacking} = 1;
                $player{attack_frame} = 0;
                $player{attack_timer} = 0;
            }
        }
    }

    # ------------------- Движение (если не атакуем) --------------------
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
        $dx -= 1 if ($left);
        $dx += 1 if ($right);
        $dy -= 1 if ($up);
        $dy += 1 if ($down);

        if ($dx || $dy) {
            $player{moving} = 1;
            $player{x} += $dx * $player{speed};
            $player{y} += $dy * $player{speed} * 0.7;
            $player{direction} = $dx if $dx != 0;
        }
    }

    # ------------------- Анимация --------------------
    if ($player{is_attacking}) {
        $player{attack_timer}++;
        if ($player{attack_timer} >= $attack_frame_duration) {
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

    # Границы (в пределах карты)
    my $pw = 36;  # ширина спрайта
    my $ph = 40;  # высота спрайта
    $player{x} = 0  if $player{x} < 0;
    $player{x} = $map_w - $pw if $player{x} > $map_w - $pw;
    $player{y} = 0  if $player{y} < 0;
    $player{y} = $map_h - $ph if $player{y} > $map_h - $ph;

    # ------------------- Рендер --------------------
    SDL_SetRenderDrawColor($renderer, 0, 0, 0, 255);
    SDL_RenderClear($renderer);

    # Карта
    SDL_RenderCopy($renderer, $map_texture, undef, $map_rect);

    # Персонаж
    my ($current_texture, $src_w, $src_h, $dst_w, $dst_h, $frame_index);
    if ($player{is_attacking}) {
        $current_texture = $attack_texture;
        $src_w = $attack_fw;
        $src_h = $attack_fh;
        $dst_w = $src_w;   # отображаем в исходном размере
        $dst_h = $src_h;
        $frame_index = $player{attack_frame};
    } else {
        $current_texture = $billy_texture;
        $src_w = $billy_fw;
        $src_h = $billy_fh;
        $dst_w = $src_w;
        $dst_h = $src_h;
        $frame_index = $player{frame};
    }

    my $packed_src = pack('iiii', $frame_index * $src_w, 0, $src_w, $src_h);
    my $src_data_ptr = $ffi->cast('string' => 'opaque', $packed_src);
    memcpy($src_rect, $src_data_ptr, 16);

    # Положение на экране: смещение карты + позиция персонажа
    my $screen_x = int($map_x + $player{x});
    my $screen_y = int($map_y + $player{y});
    my $packed_dst = pack('iiii', $screen_x, $screen_y, $dst_w, $dst_h);
    my $dst_data_ptr = $ffi->cast('string' => 'opaque', $packed_dst);
    memcpy($dst_rect, $dst_data_ptr, 16);

    my $flip = ($player{direction} < 0) ? 1 : 0;
    SDL_RenderCopyEx($renderer, $current_texture, $src_rect, $dst_rect, 0, undef, $flip);

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# Очистка
free($map_rect);
free($src_rect);
free($dst_rect);
free($event_ptr);
free($keys_buf);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();
print "Игра закрыта.\n";