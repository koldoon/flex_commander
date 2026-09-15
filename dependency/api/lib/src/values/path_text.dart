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

/// Корень адреса: `/` у локального пути, `схема://хост` у адресного.
///
/// Пусто — это не адрес: у подписи, выставленной командой («найдено 12»), ни
/// корня, ни разделителей нет, и делить её не на что.
///
/// Одно правило на всё приложение: по нему режется путь, когда он не влезает
/// (`trimTextHead`), и по нему же он разбирается на звенья
/// (`docs/spec/panel-crumbs.md`, §2). Два правила однажды разошлись бы.
String pathRootOf(String path) {
  final scheme = path.indexOf('://');
  if (scheme >= 0) {
    final slash = path.indexOf('/', scheme + 3);
    return slash < 0 ? path : path.substring(0, slash);
  }
  return path.startsWith('/') ? '/' : '';
}
