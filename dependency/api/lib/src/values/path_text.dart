/// Путь так, как его показывают и запоминают.
///
/// Хвостовой разделитель ничего не значит — `/home/docs` и `/home/docs/` это
/// один каталог, — но в списке путей он вреден вдвойне: строка выглядит иначе,
/// чем такая же без него, и в ней **нет последнего звена**, которое списки
/// набирают ярким (`docs/spec/session-history.md`, §9).
///
/// Корень не трогается: там кроме разделителя ничего и нет. Не трогается и
/// голая схема (`ssh://`) — обрезать её значило бы получить строку, которую
/// уже не открыть.
String pathWithoutTrailingSlash(String path) {
  if (path.length <= 1 || !path.endsWith('/')) {
    return path;
  }
  final trimmed = path.substring(0, path.length - 1);
  return trimmed.endsWith(':/') || trimmed.endsWith('/') ? path : trimmed;
}
