import 'dart:convert';
import 'dart:typed_data';

/// Настоящие картинки для тестов — маленькие, но всех тех форматов, за которые
/// просмотрщик берётся.
///
/// Именно настоящие, а не выдуманные байты: размеры и формат читаются из
/// заголовка движком показа, и подделка проверяла бы наш разбор вместо его.
Uint8List imageOf(String base64Data) => base64Decode(base64Data);

/// PNG 6×4.
const String pngData =
    'iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAIAAAAiZtkUAAAAFElEQVR4nGM8oaHBgAqY0PhECwEAUwwBIDEmvqgAAAAASUVORK5CYII=';

/// PNG 400×300 — крупнее любого окна в тестах: на нём видно «точка в точку».
const String bigPngData =
    'iVBORw0KGgoAAAANSUhEUgAAAZAAAAEsCAIAAABi1XKVAAAD8klEQVR4nO3UQQ3AIADAQJgQhKEYWbPAjzS5U9BX59pnABR8rwMAbhkWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVhAhmEBGYYFZBgWkGFYQIZhARmGBWQYFpBhWECGYQEZhgVkGBaQYVjAqPgB3dwDmOx4trEAAAAASUVORK5CYII=';

/// GIF 4×2.
const String gifData = 'R0lGODdhBAACAIEAAMgoKAAAAAAAAAAAACwAAAAABAACAAAIBwABCBwoMCAAOw==';

/// BMP 2×2.
const String bmpData =
    'Qk1GAAAAAAAAADYAAAAoAAAAAgAAAAIAAAABABgAAAAAABAAAADEDgAAxA4AAAAAAAAAAAAAKCjIKCjIAAAoKMgoKMgAAA==';

/// WEBP 5×5.
const String webpData = 'UklGRjoAAABXRUJQVlA4IC4AAACQAQCdASoFAAUAAUAmJaACdLoAA5gA/vCbQ/4DdfFtMv/ucD/uyf/2yf+pAAAA';

/// SVG 24×16 — с `viewBox`, как рисуют значки.
const String svgSource =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 16">'
    '<rect width="24" height="16" fill="#1e63e8"/></svg>';

/// SVG без `viewBox`, но со сторонами: размеры берутся из них.
const String svgSizedSource =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="7">'
    '<rect width="10" height="7" fill="#000"/></svg>';

/// Разметка, которая не разбирается: тег не закрыт.
const String brokenSvgSource = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 16"><rect ';
