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
    this.canStream = false,
    this.canReceive = false,
    this.level = 0,
    this.isOpen = false,
    this.hasBranches = false,
    this.sizeIsFinal = true,
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
  /// Нужен тем, кто разговаривает с системой: перетаскиванию наружу (система
  /// умеет брать файлы по имени в файловой системе, а внутри архива и на
  /// сервере такого имени нет вовсе, и оттуда отдаются обещанные файлы) и
  /// иконкам, которые спрашивают у системы её значок. Значением, а не
  /// проверкой умения источника: строка списка находок бывает откуда угодно,
  /// и решать это надо о ней, а не о панели.
  ///
  /// **У «..» он есть, хотя [path] пуст.** Это не противоречие: `path`
  /// опознаёт строку — по нему её запоминают, и чужой адрес подменял бы
  /// настоящий каталог, — а `realPath` ничего не опознаёт и отвечает на другой
  /// вопрос. Каталог, в который ведёт «..», настоящий, и система знает о нём
  /// столько же, сколько о любом другом.
  final String realPath;

  /// Что умеет источник **этой строки**: отдать содержимое и принять его.
  ///
  /// Значением, а не вопросом к панели: строка списка находок бывает откуда
  /// угодно, и завтра — из избранного, где местные каталоги, серверы и архивы
  /// стоят рядом (`docs/roadmap.md`, З2). Решать это надо о ней, а не о том,
  /// что показано панелью, — то же правило, что у [realPath].
  ///
  /// На них смотрит `F4`: править можно то, что умеют и отдать, и принять.
  final bool canStream;
  final bool canReceive;

  /// То же значение с новым размером.
  ///
  /// Нужно посчитанным каталогам: их размер приезжает отдельным событием, и
  /// строка обновляется на месте, без пересылки всего списка.
  FileEntry withSize(int value, {bool isFinal = true}) => FileEntry(
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
    level: level,
    isOpen: isOpen,
    hasBranches: hasBranches,
    sizeIsFinal: isFinal,
    canStream: canStream,
    canReceive: canReceive,
  );

  /// Глубина строки в списке: 0 у корневых, дальше по вложенности.
  ///
  /// Заполняет её маппер вида в ядре (`docs/spec/panel-node-list.md`, §4);
  /// читает только тот вид, который рисует ветви. Прочим это ноль, и они его
  /// не замечают.
  final int level;

  /// Ветвь раскрыта: её содержимое стоит в списке следом.
  final bool isOpen;

  /// Внутри ветви есть свои ветви.
  ///
  /// Заполняет это дерево одних каталогов, и заполняет **не сразу**: узнать
  /// ответ — значит прочитать каталог, а читать все подряд ради знака
  /// раскрытия долго. Поэтому по умолчанию здесь `false`, знаки появляются по
  /// мере того, как ядро дочитывает (`docs/spec/panel-view-combined.md`, §5б).
  final bool hasBranches;

  /// Размер окончателен.
  ///
  /// false — это **половина**: обход каталога идёт прямо сейчас, и число
  /// вырастет. Признак рядом с числом, а не догадка по другим полям: половина
  /// и настоящее иначе неразличимы, и застывшую в колонке половину некому ни
  /// узнать, ни убрать (`docs/spec/directory-sizes.md`).
  final bool sizeIsFinal;

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
