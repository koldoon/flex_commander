import '../values/file_attributes.dart';

/// Чем строка списка бывает — с точки зрения того, кто её рисует.
///
/// Не то же, что `FileType`: тот описывает объект файловой системы (сокет,
/// устройство, канал), а здесь перечислено то, от чего зависит показ и
/// поведение — иконка, вход по `Enter`, разворот ссылки.
enum EntryKind {
  /// Псевдострока «..»: у неё есть только имя, и вход по ней ведёт наверх.
  parent,
  directory,
  file,
  link,
}

/// Строка списка — то, чем интерфейс рисует таблицу.
///
/// Значение, а не узел: узлы живут в ядре вместе с деревом и через границу не
/// ходят (`docs/spec/client-server.md`, §4.1). Здесь ровно то, что нужно
/// показать строку и решить, что с ней делать, — и ничего сверх того.
///
/// Полей немного, но список бывает в десять тысяч строк, и каждое поле едет
/// столько же раз: всё, что можно не везти, здесь не лежит. Расширение,
/// например, не поле, а толкование имени, и делает его тот, кто показывает.
class FileEntry {
  const FileEntry({
    required this.name,
    required this.kind,
    required this.path,
    this.size = unknownSize,
    this.directoryPath = '',
    this.modified,
    this.created,
    this.accessed,
    this.attributes = const FileAttributes.unknown(),
    this.executable = false,
    this.broken = false,
    this.linkToDirectory = false,
    this.reference = '',
    this.scheme = '',
    this.realPath = '',
  });

  /// Размер неизвестен: у каталога, пока его не обошли, и у того, о чьём
  /// размере источник молчит.
  static const int unknownSize = -1;

  final String name;
  final EntryKind kind;

  /// Полный путь со схемой — он же адрес строки для ядра.
  ///
  /// У «..» пути нет: псевдострока показывает чужой каталог, и запомненная по
  /// его пути она подменяла бы собой настоящий (`spec/isolated-core.md`, §4.3.2
  /// — урок, за который уже заплачено).
  final String path;

  /// Каталог объекта — тем же текстом, каким он показан в колонке пути.
  ///
  /// Значением, а не вычислением из [path]: разделители у каждого источника
  /// свои, и складывать путь умеет только он.
  final String directoryPath;

  final int size;
  final DateTime? modified;
  final DateTime? created;
  final DateTime? accessed;
  final FileAttributes attributes;

  /// Файл исполняемый: у него своя иконка, и `Enter` на нём значит «запустить».
  final bool executable;

  /// Ссылка никуда не ведёт или объект недоступен.
  final bool broken;

  /// Ссылка ведёт в каталог: `Enter` на ней входит, а не открывает.
  final bool linkToDirectory;

  /// На что указывает ссылка — как записано в ней самой.
  final String reference;

  /// Откуда объект: `fs`, `zip`, `sftp`.
  ///
  /// У строки, а не только у панели: список находок собран из разных
  /// источников, и «откуда это» у каждой строки своё.
  final String scheme;

  /// Путь, что-то значащий **вне приложения**; пусто — такого нет.
  ///
  /// Нужен ровно одному — перетаскиванию наружу: система умеет брать файлы
  /// по имени в файловой системе, а внутри архива и на сервере такого имени
  /// нет вовсе, и оттуда отдаются обещанные файлы. Значением, а не проверкой
  /// умения источника: строка списка находок бывает откуда угодно, и решать
  /// это надо о ней, а не о панели.
  final String realPath;

  /// То же значение с новым размером.
  ///
  /// Нужно посчитанным каталогам: их размер приезжает отдельным событием, и
  /// строка обновляется на месте, без пересылки всего списка.
  FileEntry withSize(int value) => FileEntry(
    name: name,
    kind: kind,
    path: path,
    realPath: realPath,
    directoryPath: directoryPath,
    size: value,
    modified: modified,
    created: created,
    accessed: accessed,
    attributes: attributes,
    executable: executable,
    broken: broken,
    linkToDirectory: linkToDirectory,
    reference: reference,
    scheme: scheme,
  );

  bool get isDirectory => kind == EntryKind.directory;

  bool get isParent => kind == EntryKind.parent;

  bool get isLink => kind == EntryKind.link;

  /// Скрытый по имени. Правило одно на все источники: точка в начале.
  bool get hidden => name.startsWith('.');

  /// Войти можно: каталог, «..» или ссылка на каталог.
  bool get canEnter => kind == EntryKind.directory || kind == EntryKind.parent || (isLink && linkToDirectory);

  @override
  String toString() => 'FileEntry($name, ${kind.name})';
}
