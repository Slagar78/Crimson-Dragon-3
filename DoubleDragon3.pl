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

my $window   = SDL_CreateWindow("Crimson Dragon 3", 100, 100, 1024, 600, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0);
die "Renderer failed" unless $renderer;

# Память для событий (SDL_Event – 56 байт)
my $event_ptr = malloc(56);
die "malloc event failed" unless $event_ptr;

# Загрузка спрайта (4 кадра 26x40 в строке)
my $surface = IMG_Load("Dragon/Billy.png");
die "Не удалось загрузить Dragon/Billy.png: " . SDL_GetError() unless $surface;
my $texture = SDL_CreateTextureFromSurface($renderer, $surface);
SDL_FreeSurface($surface);

my $frame_width  = 26;
my $frame_height = 40;

# Персонаж
my %player = (
    x          => 400,
    y          => 380,
    frame      => 3,          # стоячий кадр
    anim_timer => 0,
    direction  => 1,
    speed      => 4.0,
    moving     => 0,
);

# Прямоугольники
my $src_rect = malloc(16);
my $dst_rect = malloc(16);

# Буфер для состояний клавиатуры
my $keys_buf = malloc(512);
die "malloc keys failed" unless $keys_buf;

my $running = 1;

print "Crimson Dragon 3 запущена\n";
print "Управление: стрелки или WASD\n";
print "Закрытие: крестик или Esc\n\n";

# Вспомогательная строка для событий (будет использоваться как буфер)
my $event_str = "\0" x 56;
my $event_str_ptr = $ffi->cast('string' => 'opaque', $event_str);

while ($running) {
    # === Обработка событий (надёжный способ) ===
    while (SDL_PollEvent($event_ptr)) {
        # Копируем событие в строку event_str
        memcpy($event_str_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));   # Uint32

        if ($type == 0x100) {          # SDL_QUIT
            $running = 0;
        }
        elsif ($type == 0x300) {       # SDL_KEYDOWN
            # keysym.sym лежит по смещению 20 (см. структуру SDL_KeyboardEvent)
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 27) {          # SDLK_ESCAPE
                $running = 0;
            }
        }
    }

    # === Клавиатура (аналогично через строку) ===
    my $keys_ptr = SDL_GetKeyboardState(undef);
    my $keys_str = "\0" x 512;
    my $keys_str_ptr = $ffi->cast('string' => 'opaque', $keys_str);
    memcpy($keys_str_ptr, $keys_ptr, 512);

    my $left  = vec($keys_str, 0x50, 8);   # Left
    my $a     = vec($keys_str, 0x04, 8);   # A
    my $right = vec($keys_str, 0x4F, 8);   # Right
    my $d     = vec($keys_str, 0x07, 8);   # D
    my $up    = vec($keys_str, 0x52, 8);   # Up
    my $w     = vec($keys_str, 0x1A, 8);   # W
    my $down  = vec($keys_str, 0x51, 8);   # Down
    my $s     = vec($keys_str, 0x16, 8);   # S

    $player{moving} = 0;

    my $dx = 0;
    my $dy = 0;
    $dx -= 1 if ($left || $a);
    $dx += 1 if ($right || $d);
    $dy -= 1 if ($up || $w);
    $dy += 1 if ($down || $s);

    if ($dx || $dy) {
        $player{moving} = 1;
        $player{x} += $dx * $player{speed};
        $player{y} += $dy * $player{speed} * 0.7;
        $player{direction} = $dx if $dx != 0;
    } else {
        $player{moving} = 0;
    }

    # Анимация
    if ($player{moving}) {
        if (++$player{anim_timer} >= 5) {
            $player{anim_timer} = 0;
            $player{frame} = ($player{frame} + 1) % 3;
        }
    } else {
        $player{frame} = 3;
    }

    # Границы
    $player{x} = 40  if $player{x} < 40;
    $player{x} = 920 if $player{x} > 920;
    $player{y} = 200 if $player{y} < 200;
    $player{y} = 520 if $player{y} > 520;

    # Заполняем SDL_Rect
    my $packed_src = pack('iiii', $player{frame} * $frame_width, 0, $frame_width, $frame_height);
    my $src_data_ptr = $ffi->cast('string' => 'opaque', $packed_src);
    memcpy($src_rect, $src_data_ptr, 16);

    my $packed_dst = pack('iiii', int($player{x}), int($player{y}), 52, 80);
    my $dst_data_ptr = $ffi->cast('string' => 'opaque', $packed_dst);
    memcpy($dst_rect, $dst_data_ptr, 16);

    # Рендер
    SDL_SetRenderDrawColor($renderer, 25, 25, 70, 255);
    SDL_RenderClear($renderer);

    my $flip = ($player{direction} < 0) ? 1 : 0;
    SDL_RenderCopyEx($renderer, $texture, $src_rect, $dst_rect, 0, undef, $flip);

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# Очистка
free($src_rect);
free($dst_rect);
free($event_ptr);
free($keys_buf);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();

print "Игра закрыта.\n";