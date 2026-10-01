import 'package:fc_api/fc_api.dart';

/// Место на боковой полосе: адрес и, если дано, своё имя.
///
/// Адрес — строка, какой её набирают в `Cmd-F1`: `~/Downloads`, `ssh://shark/home`,
/// путь в архив. Своего разбора у полосы нет: переходит туда тот же
/// `Session.openPath`, что и окно адреса (`docs/spec/favorites-sidebar.md`, §3).
class Place implements Serializable {
  Place({this.address = '', this.name});

  String address;

  /// Своё имя; null — последнее звено адреса.
  String? name;

  @override
  void fromMap(Map<String, dynamic> m) {
    address = extract(address, m['address']);
    final stored = m['name'];
    name = stored is String && stored.isNotEmpty ? stored : null;
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['address'] = address;
    if (name case final name?) {
      m['name'] = name;
    }
  }
}

/// Что за место — по адресу, а не по имени: им выбирается значок и имя по
/// умолчанию.
enum PlaceKind { home, desktop, documents, downloads, applications, volume, server, archive, folder }

/// Адреса мест знает только полоса, и сравнивает она их по-своему: `~` и
/// домашний каталог целиком — одно место, хвостовой разделитель — не отличие.
abstract final class PlaceAddress {
  /// Расширения, по которым путь читается как место в архиве.
  ///
  /// Список, а не спрос у модулей архивов: ошибка здесь стоит одного значка, а
  /// не перехода — переходит всё равно `openPath`.
  static const List<String> archiveExtensions = [
    '.zip',
    '.7z',
    '.tar',
    '.tgz',
    '.tar.gz',
    '.tbz2',
    '.tar.bz2',
    '.txz',
    '.tar.xz',
    '.jar',
    '.rar',
  ];

  /// Адрес так, как его хранить: внутри домашнего каталога — через `~`.
  static String normalize(String address, {String home = ''}) {
    var value = address.trim();
    if (value.length > 1 && value.endsWith('/') && !value.endsWith('://')) {
      value = value.substring(0, value.length - 1);
    }
    if (home.isNotEmpty && home != '/') {
      if (value == home) {
        return '~';
      }
      if (value.startsWith('$home/')) {
        return '~${value.substring(home.length)}';
      }
    }
    return value;
  }

  static PlaceKind kindOf(String address) {
    final value = normalize(address);
    if (value.contains('://')) {
      return PlaceKind.server;
    }
    switch (value) {
      case '~':
        return PlaceKind.home;
      case '~/Desktop':
        return PlaceKind.desktop;
      case '~/Documents':
        return PlaceKind.documents;
      case '~/Downloads':
        return PlaceKind.downloads;
      case '/Applications' || '~/Applications':
        return PlaceKind.applications;
      case '/':
        return PlaceKind.volume;
    }
    if (value.startsWith('/Volumes/') && !value.substring('/Volumes/'.length).contains('/')) {
      return PlaceKind.volume;
    }
    final lower = value.toLowerCase();
    for (final extension in archiveExtensions) {
      if (lower.endsWith(extension) || lower.contains('$extension/')) {
        return PlaceKind.archive;
      }
    }
    return PlaceKind.folder;
  }

  /// Имя по умолчанию — ключ перевода у знакомых мест, последнее звено у
  /// прочих.
  static String defaultName(String address) {
    final value = normalize(address);
    switch (kindOf(value)) {
      case PlaceKind.home:
        return 'Home';
      case PlaceKind.desktop:
        return 'Desktop';
      case PlaceKind.documents:
        return 'Documents';
      case PlaceKind.downloads:
        return 'Downloads';
      case PlaceKind.applications:
        return 'Applications';
      case PlaceKind.volume when value == '/':
        return 'Root';
      default:
        break;
    }
    final slash = value.lastIndexOf('/');
    final tail = slash < 0 ? value : value.substring(slash + 1);
    return tail.isEmpty ? value : tail;
  }

  /// Переводится ли имя по умолчанию: знакомое место подписано, как в Finder,
  /// на языке приложения, а последнее звено каталога — как есть.
  static bool isTranslatedName(String address) => switch (kindOf(address)) {
    PlaceKind.home || PlaceKind.desktop || PlaceKind.documents || PlaceKind.downloads || PlaceKind.applications => true,
    PlaceKind.volume => normalize(address) == '/',
    _ => false,
  };
}
