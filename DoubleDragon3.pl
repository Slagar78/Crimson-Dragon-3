use strict;
use warnings;
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

BEGIN { $ENV{PATH} .= ';D:\perl5\share\SDL2\lib'; }

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

# SDL функции
$ffi->attach( SDL_Init => ['uint'] => 'int' );
$ffi->attach( SDL_GetError => [] => 'string' );
$ffi->attach( SDL_CreateWindow => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer => ['opaque','int','uint'] => 'opaque' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear => ['opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent => ['opaque'] => 'void' );
$ffi->attach( SDL_PollEvent => ['opaque'] => 'int' );
$ffi->attach( SDL_Delay => ['uint'] => 'void' );
$ffi->attach( SDL_DestroyRenderer => ['opaque'] => 'void' );
$ffi->attach( SDL_DestroyWindow => ['opaque'] => 'void' );
$ffi->attach( SDL_Quit => [] => 'void' );
$ffi->attach( SDL_GetKeyboardState => ['opaque'] => 'opaque' );
$ffi->attach( SDL_FreeSurface => ['opaque'] => 'void' );

# SDL_image
$ffi->attach( IMG_Load => ['string'] => 'opaque' );
$ffi->attach( IMG_Init => ['int'] => 'int' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque'] => 'opaque' );
$ffi->attach( SDL_RenderCopyEx => ['opaque','opaque','opaque','opaque','double','opaque','int'] => 'int' );

# Инициализация
die "SDL_Init failed: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init failed" unless IMG_Init(2) & 2;

my $window = SDL_CreateWindow("Double Dragon 3 - Perl Remaster", 100, 100, 1024, 600, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0);
die "Renderer failed: " . SDL_GetError() unless $renderer;

my $event_ptr = malloc(56);

# Загрузка спрайта
my $surface = IMG_Load("D:/Perl/Dragon/Billy.png");
die "Не удалось загрузить Billy.png: " . SDL_GetError() unless $surface;
my $texture = SDL_CreateTextureFromSurface($renderer, $surface);
SDL_FreeSurface($surface);

my $frame_width = 24;
my $frame_height = 40;

# Персонаж
my %player = (
    x => 400,
    y => 380,
    frame => 0,
    anim_timer => 0,
    direction => 1,     # 1 = вправо, -1 = влево
    speed => 4.0,
    moving => 0,
);

my $src_rect = malloc(16);
my $dst_rect = malloc(16);

my $running = 1;

print "Double Dragon 3 / TMNT стиль\n";
print "Стрелки или WASD — движение в 4 стороны\n";

while ($running) {
    while (SDL_PollEvent($event_ptr)) {
        my $type = $ffi->cast('opaque' => 'uint32', $event_ptr);
        if ($type == 0x100) { $running = 0; }
    }

    my $keys_ptr = SDL_GetKeyboardState(undef);
    my $keys = $ffi->cast('opaque' => 'uint8[512]', $keys_ptr);

    $player{moving} = 0;

    my $dx = 0;
    my $dy = 0;

    # Движение
    if ($keys->[80] || $keys->[4])  { $dx -= 1; }  # Left / A
    if ($keys->[79] || $keys->[7])  { $dx += 1; }  # Right / D
    if ($keys->[82] || $keys->[19]) { $dy -= 1; }  # Up / W
    if ($keys->[81] || $keys->[22]) { $dy += 1; }  # Down / S

    if ($dx != 0 || $dy != 0) {
        $player{moving} = 1;
        
        # Изменяем позицию
        $player{x} += $dx * $player{speed};
        $player{y} += $dy * $player{speed} * 0.7;   # чуть медленнее по вертикали (изометрия)

        # Запоминаем последнее горизонтальное направление
        if ($dx != 0) {
            $player{direction} = $dx;
        }
    }

    # Анимация
    if ($player{moving}) {
        if (++$player{anim_timer} >= 5) {
            $player{anim_timer} = 0;
            $player{frame} = ($player{frame} + 1) % 3;
        }
    } else {
        $player{frame} = 0;
    }

    # Границы
    $player{x} = 40 if $player{x} < 40;
    $player{x} = 920 if $player{x} > 920;
    $player{y} = 200 if $player{y} < 200;
    $player{y} = 520 if $player{y} > 520;

    # Рендер
    SDL_SetRenderDrawColor($renderer, 25, 25, 70, 255);
    SDL_RenderClear($renderer);

    my $packed_src = pack('iiii', $player{frame} * $frame_width, 0, $frame_width, $frame_height);
    memcpy($src_rect, $ffi->cast('string' => 'opaque', $packed_src), 16);

    my $packed_dst = pack('iiii', int($player{x}), int($player{y}), 48, 80);
    memcpy($dst_rect, $ffi->cast('string' => 'opaque', $packed_dst), 16);

    my $flip = ($player{direction} < 0) ? 1 : 0;
    SDL_RenderCopyEx($renderer, $texture, $src_rect, $dst_rect, 0, undef, $flip);

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

free($src_rect);
free($dst_rect);
free($event_ptr);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();

print "Игра закрыта.\n";