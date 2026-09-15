import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'file_type_icon.dart';

/// Имена штатных колонок.
///
/// Внешний контракт: они лежат в `settings.json`, ездят в протоколе и
/// упоминаются в справке. Сохранены с тех пор, когда колонки были
/// перечислением, — поэтому старые настройки читаются без миграции
/// (`docs/spec/column-registry.md`, §9).
abstract final class FsColumns {
  static const String icon = 'icon';
  static const String name = 'name';
  static const String tree = 'tree';
  static const String path = 'path';
  static const String ext = 'ext';
  static const String size = 'size';
  static const String modified = 'modified';
  static const String created = 'created';
  static const String accessed = 'accessed';
  static const String attributes = 'attributes';
  static const String owner = 'owner';
  static const String group = 'group';
}

/// Паспорта штатных колонок — одни на обе половины модуля.
///
/// Ширины — по референсу, в тех же точках экрана, что и остальные размеры.
/// Колонка значка вмещает отступ, глиф и просвет до имени; настоящую её ширину
/// считает тот, кто рисует (`FileIconSize.columnWidth`): она зависит и от
/// размера значка, который настраивается. Здесь — значение для тех, у кого
/// темы под рукой нет: разбора раскладки и тестов.
abstract final class FsColumnSpecs {
  static const ColumnSpec icon = ColumnSpec(id: FsColumns.icon, width: 28, minWidth: 28, pinned: true, sortable: false);

  static const ColumnSpec name = ColumnSpec(
    id: FsColumns.name,
    title: 'Name',
    width: 0,
    minWidth: 90,
    pinned: true,
    flexible: true,
  );

  /// Ветвь дерева: отступ по глубине, знак раскрытия, значок и имя.
  ///
  /// Колонка, а не особый вид строки: дерево показывает то же, что список, — и
  /// рядом с ним встают те же размер и дата (`docs/spec/panel-view-tree.md`,
  /// §4). Сортируется именем — как колонка имени, которой она и является.
  ///
  /// В раскладку панели не входит: таблица ветвей не рисует, и предлагать эту
  /// колонку в меню видимости было бы обещанием несбыточного. Дерево ставит её
  /// себе само.
  static const ColumnSpec tree = ColumnSpec(
    id: FsColumns.tree,
    title: 'Tree',
    width: 0,
    pinned: true,
    flexible: true,
    inLayout: false,
  );

  /// Каталог, в котором объект лежит.
  ///
  /// В обычном каталоге он у всех один и потому спрятан; список находок им и
  /// живёт: `main.dart` там будет десяток, и различает их только это.
  static const ColumnSpec path = ColumnSpec(id: FsColumns.path, title: 'Path', width: 160, visible: false);

  static const ColumnSpec ext = ColumnSpec(id: FsColumns.ext, title: 'Ext', width: 40, align: ColumnAlign.end);

  /// Форматы дат — одни и те же у трёх колонок, а выбирают их порознь: «Изменён»
  /// с временем и «Создан» без — законное желание
  /// (`docs/spec/column-formats.md`, §4).
  static const List<ColumnFormatSpec> dateFormats = [
    ColumnFormatSpec('date', 'dd-mm-yyyy'),
    ColumnFormatSpec('datetime', 'dd-mm-yyyy hh:mm'),
    ColumnFormatSpec('iso', 'yyyy-mm-dd'),
    ColumnFormatSpec('isotime', 'yyyy-mm-dd hh:mm'),
  ];

  /// Имя или число — у владельца и у группы.
  static const List<ColumnFormatSpec> ownerFormats = [
    ColumnFormatSpec('name', 'Name'),
    ColumnFormatSpec('id', 'Number'),
  ];

  static const ColumnSpec size = ColumnSpec(
    id: FsColumns.size,
    title: 'Size',
    width: 64,
    align: ColumnAlign.end,
    formats: [
      ColumnFormatSpec('auto', 'Auto'),
      ColumnFormatSpec('bytes', 'Bytes'),
      ColumnFormatSpec('binary', 'KB, MB, GB'),
      ColumnFormatSpec('decimal', 'kB, MB, GB'),
    ],
  );

  static const ColumnSpec modified = ColumnSpec(
    formats: dateFormats,
    id: FsColumns.modified,
    title: 'Modified',
    width: 88,
    align: ColumnAlign.end,
  );

  static const ColumnSpec created = ColumnSpec(
    formats: dateFormats,
    id: FsColumns.created,
    title: 'Created',
    width: 88,
    visible: false,
    align: ColumnAlign.end,
  );

  static const ColumnSpec accessed = ColumnSpec(
    formats: dateFormats,
    id: FsColumns.accessed,
    title: 'Accessed',
    width: 88,
    visible: false,
    align: ColumnAlign.end,
  );

  static const ColumnSpec attributes = ColumnSpec(
    id: FsColumns.attributes,
    title: 'Attributes',
    width: 88,
    visible: false,
    formats: [
      ColumnFormatSpec('letters', 'rwxr-xr-x'),
      ColumnFormatSpec('octal', '755'),
      ColumnFormatSpec('both', 'rwxr-xr-x 755'),
    ],
  );

  /// Кто хозяин объекта. Скрыта, как и права: в своём каталоге владелец у всех
  /// один, и спрашивают о нём тогда, когда что-то не открылось
  /// (`docs/spec/owner-columns.md`, §2).
  static const ColumnSpec owner = ColumnSpec(
    id: FsColumns.owner,
    title: 'Owner',
    width: 96,
    visible: false,
    formats: ownerFormats,
  );

  static const ColumnSpec group = ColumnSpec(
    id: FsColumns.group,
    title: 'Group',
    width: 96,
    visible: false,
    formats: ownerFormats,
  );

  /// Порядок объявления — он же порядок колонок в новой панели.
  static const List<ColumnSpec> all = [
    icon,
    name,
    tree,
    path,
    ext,
    size,
    modified,
    created,
    accessed,
    attributes,
    owner,
    group,
  ];
}

/// Ядровая половина штатных колонок: сравнения.
///
/// Всё, что раньше было `switch` по перечислению в `node_sorting.dart`.
void installColumnSorting(BackendRegistry registry) {
  // У значка сравнения нет: `sortable: false` — щёлкать по нему в шапке негде.
  registry.column(FsColumnSpecs.icon);
  registry.column(FsColumnSpecs.name, compare: (_) => (a, b) => naturalCompare(a.name, b.name));
  // Колонка дерева и колонка имени — одна и та же колонка, нарисованная
  // по-разному (`docs/spec/panel-node-list.md`, §5).
  registry.column(FsColumnSpecs.tree, compare: (_) => (a, b) => naturalCompare(a.name, b.name));
  registry.column(FsColumnSpecs.path, compare: (_) => (a, b) => naturalCompare(_directoryOf(a), _directoryOf(b)));
  registry.column(FsColumnSpecs.ext, compare: _extensionComparator);
  registry.column(FsColumnSpecs.size, compare: (_) => (a, b) => a.size.compareTo(b.size));
  registry.column(FsColumnSpecs.modified, compare: (_) => (a, b) => _dates(_fileOf(a)?.modified, _fileOf(b)?.modified));
  registry.column(FsColumnSpecs.created, compare: (_) => (a, b) => _dates(_fileOf(a)?.created, _fileOf(b)?.created));
  registry.column(FsColumnSpecs.accessed, compare: (_) => (a, b) => _dates(_fileOf(a)?.accessed, _fileOf(b)?.accessed));
  registry.column(FsColumnSpecs.attributes, compare: (_) => (a, b) => naturalCompare(_modeOf(a), _modeOf(b)));
  // По тому же, что и показано: имя, если оно есть, иначе число. Сравнивать по
  // скрытому числу значило бы раскладывать список не в том порядке, в каком он
  // читается.
  registry.column(FsColumnSpecs.owner, compare: (_) => (a, b) => naturalCompare(_ownerOf(a), _ownerOf(b)));
  registry.column(FsColumnSpecs.group, compare: (_) => (a, b) => naturalCompare(_groupOf(a), _groupOf(b)));
}

/// Экранная половина штатных колонок: ячейки.
///
/// Всё, что раньше было `switch` по перечислению в `FileTableRow`.
void installColumnCells(FrontendRegistry registry) {
  registry.column(
    FsColumnSpecs.icon,
    build:
        (context, cell) => Padding(
          // Значок прижат к левому краю строки: `left="30"` у `iconLabel`.
          padding: EdgeInsets.only(left: FcTheme.of(context).metrics.iconLeftPadding),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FileTypeIcon(entry: cell.entry, selected: cell.selected, contentOf: cell.contentOf),
          ),
        ),
  );
  // Расширение показывается отдельной колонкой, поэтому из имени убирается.
  registry.column(
    FsColumnSpecs.name,
    text: (cell) => _splits(cell) ? cell.naming.split(cell.entry.name).base : cell.entry.name,
  );
  // Ветвь рисует дерево — со своим отступом и знаком раскрытия; строка списка
  // про это ничего не знает (`docs/spec/panel-view-tree.md`, §4).
  registry.column(FsColumnSpecs.tree, text: (cell) => cell.entry.name);
  // Каталог объекта, а не его собственный путь: имя уже показано рядом.
  registry.column(FsColumnSpecs.path, text: (cell) => cell.entry.directoryPath);
  registry.column(FsColumnSpecs.ext, text: (cell) => _splits(cell) ? cell.naming.split(cell.entry.name).extension : '');
  registry.column(FsColumnSpecs.size, text: (cell) => formatSize(cell.entry.size, SizeFormat.byId(cell.format)));
  registry.column(
    FsColumnSpecs.modified,
    text: (cell) => formatDate(cell.entry.modified, DateFormat.byId(cell.format)),
  );
  registry.column(FsColumnSpecs.created, text: (cell) => formatDate(cell.entry.created, DateFormat.byId(cell.format)));
  registry.column(
    FsColumnSpecs.accessed,
    text: (cell) => formatDate(cell.entry.accessed, DateFormat.byId(cell.format)),
  );
  registry.column(
    FsColumnSpecs.attributes,
    text: (cell) => formatMode(cell.entry.attributes, ModeFormat.byId(cell.format)),
  );
  // Имя, число или пусто — по тому, что известно источнику. Пустая ячейка
  // честнее выдуманной: у архива хозяина нет вовсе.
  // Формат `id` не выдумывает числа там, где их нет, — он лишь запрещает
  // подставлять имя там, где оно есть.
  registry.column(
    FsColumnSpecs.owner,
    text:
        (cell) => cell.format == 'id' ? (cell.entry.attributes.uid?.toString() ?? '') : cell.entry.attributes.ownerText,
  );
  registry.column(
    FsColumnSpecs.group,
    text:
        (cell) => cell.format == 'id' ? (cell.entry.attributes.gid?.toString() ?? '') : cell.entry.attributes.groupText,
  );
}

/// Имя делится на имя и расширение, только если колонка расширений видима.
///
/// У каталога расширения нет: `my.backup` это не «файл .backup». Решает это
/// тот, кто показывает, — расширение вообще не свойство файла, а толкование
/// имени.
bool _splits(ColumnCell cell) => !cell.entry.isDirectory && cell.shows(FsColumns.ext);

/// Расширение сравнивается тем же правилом, каким рисуется колонка.
///
/// Иначе показ и порядок разойдутся: имя стояло бы в списке под одним
/// расширением, а сортировалось по другому. Правило это настраивается
/// (`docs/spec/compound-extensions.md`), поэтому берётся службой.
NodeComparator _extensionComparator(FcServices services) {
  final naming = services.resolve<FileNaming>();
  String extensionOf(FsNode node) => _fileOf(node) == null ? '' : naming.split(node.name).extension;
  return (a, b) => naturalCompare(extensionOf(a), extensionOf(b));
}

FileNode? _fileOf(FsNode node) => node is FileNode ? node : null;

/// Каталог объекта — тем же текстом, каким он показан в колонке пути.
String _directoryOf(FsNode node) => node.parentDirectory?.displayPath ?? '';

String _modeOf(FsNode node) => _fileOf(node)?.attributes.modeString ?? '';

String _ownerOf(FsNode node) => _fileOf(node)?.attributes.ownerText ?? '';

String _groupOf(FsNode node) => _fileOf(node)?.attributes.groupText ?? '';

/// Отсутствующая дата меньше любой заданной.
int _dates(DateTime? a, DateTime? b) {
  if (a == null) {
    return b == null ? 0 : -1;
  }
  if (b == null) {
    return 1;
  }
  return a.compareTo(b);
}
