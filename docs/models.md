# Слой моделей

Основа взята из референса (`ru.koldoon.fc.m.*`) и переложена на Dart.
Главная мысль: панель показывает **каталог в дереве узлов**, а не «список файлов»,
а всё чтение и изменение дерева спрятано за `TreeProvider`.

Слой не зависит от Flutter (импорт `package:flutter/foundation.dart` допустим только
ради `ChangeNotifier`/`@immutable`, а в `model/` он не нужен вообще).

## 1. Дерево узлов

### `FsNode`

```dart
/// Общий узел дерева. Аналог INode из референса.
abstract class FsNode {
  /// Родительский узел. null только у корня провайдера.
  FsNode? get parent;

  /// Отображаемое имя, оно же ключ узла внутри родителя.
  String get name;

  /// Размер в байтах. -1, если неизвестен (каталоги до подсчёта, битые ссылки).
  /// Размер входит в общий интерфейс, потому что почти все операции считают
  /// суммарный объём данных к обработке — это решение референса, оно оправдано.
  int get size;

  /// Текст для строки состояния, когда узел под курсором.
  /// Для ссылки — "name -> target".
  String get info;

  /// Полный путь строкой (см. раздел «Строки пути»).
  String get pathString;

  /// Путь от корня дерева до этого узла включительно.
  List<FsNode> get path;

  /// Ближайший вверх по дереву TreeProvider.
  TreeProvider get provider;

  /// Ближайший вверх по дереву каталог.
  DirectoryNode? get parentDirectory;
}
```

Реализация базовой части — `AbstractFsNode` с полями `_parent`, `_name`, `_size`
и обходами вверх по `parent` (как `AbstractNode` в референсе).

Узлы **имеют идентичность**: пометка объектов и восстановление курсора работают
по конкретным экземплярам. После перечитывания каталога экземпляры создаются заново,
поэтому курсор и пометка переносятся по имени — это явное правило, см.
[`state.md`](state.md#перечитывание-каталога).

### Конкретные типы

```dart
/// Файл. Базовый класс и для каталогов, и для ссылок — как в референсе.
class FileNode extends AbstractFsNode {
  FileNode({required String name, FsNode? parent});

  /// Расширение без точки. Вычисляется из имени по FILE_EXTENSION_RE.
  /// Пустое для каталогов и для имён без «настоящего» расширения.
  String extension;

  /// Тип узла.
  FileType fileType;

  /// Права доступа и флаги.
  FileAttributes attributes;

  DateTime? modified;

  /// Время последнего изменения метаданных (ctime): настоящей даты создания
  /// файла `dart:io` не отдаёт ни на одной платформе.
  DateTime? created;

  DateTime? accessed;

  bool executable;

  /// Узел не удалось прочитать целиком (нет прав, исчез во время чтения).
  bool broken;
}

/// Каталог: может содержать другие узлы.
class DirectoryNode extends FileNode {
  /// Содержимое, загруженное последним getDirectoryListing().
  /// Порядок — как вернул провайдер; сортировка живёт в PanelController.
  List<FsNode> get nodes;

  /// Перечитать содержимое. Делегирует provider.getDirectoryListing(this).
  AsyncOperation<List<FsNode>> refresh();
}

/// Символическая ссылка.
class LinkNode extends FileNode {
  /// Строка, на которую ссылка указывает (как её вернула ФС, может быть относительной).
  final String reference;

  /// Разрешённая цель; null, пока resolve() не выполнен, и у битой ссылки.
  /// Цель — **дочерний узел самой ссылки**: см. «Ссылки и два вида путей».
  FsNode? target;

  /// Тип цели, известный уже при чтении каталога: `stat` по ссылке всё равно
  /// идёт до цели, поэтому сортировка «каталоги вперёд» и выбор иконки
  /// не требуют отдельного разрешения ссылки. null у битой ссылки.
  final FileType? targetType;

  /// Ссылка ведёт в каталог.
  bool get isDirectoryLink;

  AsyncOperation<FsNode?> resolve();

  @override
  String get info => '$name -> $reference';
}

/// Псевдоузел ".." — вход в родительский каталог.
/// В отличие от референса (где был один статический PARENT_NODE на всё приложение)
/// создаётся отдельным экземпляром для каждого каталога: так проще работать
/// с пометкой и идентичностью узлов.
class ParentDirNode extends FsNode {
  ParentDirNode(DirectoryNode directory);
  @override String get name => '..';
}
```

Правила:

- `..` всегда первый в списке, вне зависимости от сортировки, и **никогда не помечается**
  (`PanelSelection.add` его игнорирует — поведение референса).
- Расширение определяется регулярным выражением референса:
  `^([^\/*?|]+)\.([^\/*?|\s]{1,12})$` — не длиннее 12 символов, без пробелов,
  имя `.gitignore` расширения не имеет. Константа `FileNode.fileExtensionRe`.
- В колонке «Имя» показывается имя **без** расширения, если оно вынесено в колонку `ext`
  и эта колонка видима; иначе — имя целиком.

### `FileType`

```dart
enum FileType {
  regular('-'),
  directory('d'),
  symbolicLink('l'),
  socket('s'),
  fifo('p'),
  blockSpecial('b'),
  characterSpecial('c');

  final String attributeChar;

  /// Разбор первого символа строки режима ("drwxr-xr-x" -> directory).
  static FileType fromAttributeChar(String char);

  /// Разбор FileSystemEntityType из dart:io.
  static FileType fromEntityType(FileSystemEntityType type);
}
```

### `FileAttributes`

```dart
class FileAttributes {
  /// Сырой mode из FileStat.mode.
  final int mode;

  /// Строка в стиле ls: "drwxr-xr-x". То, что показывает колонка «Атрибуты».
  /// Первый символ — тип объекта: `FileStat.modeString()` отдаёт только девять
  /// символов прав, тип подставляется самостоятельно.
  final String modeString;

  bool get isReadable;
  bool get isWritable;
  bool get isExecutable;

  factory FileAttributes.fromStat(FileStat stat, {FileType? type});

  /// На Windows строка режима малоинформативна: там показываются флаги RHSA.
  factory FileAttributes.fromWindowsAttributes(int flags);
}
```

## 2. Провайдеры дерева

Интерфейсы повторяют `ITreeProvider` / `ITreeEditor` / `IFilesProvider` референса.
В MVP реализуется только `LocalTreeProvider`, но панель и команды пишутся против
интерфейса — это условие для будущих архивов и удалённых ФС.

```dart
abstract interface class TreeProvider {
  /// Схема для строк пути: "fs", "zip", "sftp".
  String get scheme;

  /// Корневой каталог провайдера.
  DirectoryNode get rootDirectory;

  /// Каталог по умолчанию: сюда открывается панель, если сохранённый путь
  /// недоступен. Для локальной ФС — домашний каталог пользователя.
  String get homePath;

  /// Видимый путь узла внутри провайдера, без схемы: ссылки в нём остаются
  /// ссылками — см. «Ссылки и два вида путей».
  String pathOf(FsNode node);

  /// Разбор строки пути в узел. Достраивает всю цепочку узлов от корня,
  /// при необходимости обращаясь во вложенные провайдеры.
  AsyncOperation<FsNode?> resolvePath(String path);

  /// Чтение содержимого каталога. По завершении заполняет dir.nodes.
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir);

  /// Разрешение ссылки: заполняет link.target.
  AsyncOperation<FsNode?> resolveLink(LinkNode link);
}

/// Изменение дерева. Отдельный интерфейс: провайдер может уметь только читать
/// (архив, открытый на просмотр), и команда это проверяет через `panel.editor`.
abstract interface class TreeEditor {
  AsyncOperation<void> copy(List<FsNode> nodes, DirectoryNode destination);
  AsyncOperation<void> move(List<FsNode> nodes, DirectoryNode destination);
  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true});
  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name);
}

/// «Мост» между разными провайдерами через файлы локальной ФС.
/// Нужен, когда копируем из архива в sftp и наоборот. Реализуется после MVP.
abstract interface class FilesProvider {
  AsyncOperation<List<FileReference>> getFiles(List<FsNode> nodes, {bool followLinks = true});
  AsyncOperation<void> putFiles(List<FileReference> files, DirectoryNode toDir);
  AsyncOperation<void> purge();
}
```

### Ссылки и два вида путей

Разрешённая ссылка не подменяет себя целью, а **становится её родителем**:
цепочка узлов выглядит как `/ → etc (ссылка) → etc (каталог) → apache2`.
Правило взято из референса (`LFS_ResolveLinkOperation` + `FileNodeUtil`) и решает
главную задачу — дерево помнит, как пользователь сюда пришёл.

Отсюда два вида путей:

| | Что это | Где применяется |
|---|---|---|
| `node.pathString` (`TreeProvider.pathOf`) | **видимый** путь; имя цели ссылки в него не входит | заголовок панели, строка состояния, сохранение в настройках |
| `LocalTreeProvider.physicalPathOf` | **настоящий** путь; все ссылки развёрнуты | чтение каталогов, `stat`, файловые операции |

Для `/etc`, который на macOS ведёт в `/private/etc`, панель показывает `/etc`,
а читает `/private/etc`. Переход наверх при этом возвращает в `/`, а не в `/private`:
`parentDirectory` перешагивает через ссылку и приходит в каталог, где она лежит.
Курсор встаёт на объект, через который вошли, — на саму ссылку, а не на имя её цели
(имена могут не совпадать: `latest -> app-1.2.0`).

Цепочки ссылок разворачиваются до первого «настоящего» узла, пройденные пути
запоминаются: закольцованная ссылка не разрешается вовсе, а не уводит в бесконечность.

### Строки пути

Соглашение референса сохраняется: путь может проходить через несколько провайдеров,
части разделяются двоеточием, схема провайдера пишется перед своей частью.

```
fs:/Users/koldoon/Developer/archive.zip:zip:/subdir/document.doc
```

Отсутствующая схема означает `fs`, так что обычный `/Users/koldoon` — валидный путь.
Разбор и сборка — в `model/tree/node_path.dart`; в MVP реально используется одна часть,
но формат хранения настроек уже пишет полную строку, чтобы позже не мигрировать файл.

### `LocalTreeProvider`

Реализация поверх `dart:io` (в референсе это делалось запуском `ls`/`stat`, потому что
в AIR не было API файловой системы; здесь такой необходимости нет).

Чтение каталога:

1. `Directory(path).list(followLinks: false)` — получаем сущности;
2. `entity.stat()` для каждой — тип, размер, даты, режим;
3. если элемент не читается — узел всё равно создаётся с `broken = true`
   (одна недоступная запись не должна ронять всё чтение);
4. всё это выполняется в изоляте через `Isolate.run`, чтобы `stat()` на тысячах
   файлов не съедал кадры UI; наружу возвращается готовый список узлов;
5. скрытые элементы (`.` в начале имени) фильтруются по флагу `includeHidden`;
6. если каталог не корневой — первым элементом добавляется `ParentDirNode`.

Ошибки чтения самого каталога отдаются как `FsError`:

```dart
enum FsErrorKind { notFound, permissionDenied, notADirectory, io }

class FsError implements Exception {
  final String path;
  final FsErrorKind kind;
  final Object? cause;
}
```

`permissionDenied` не обязан быть фатальным: операция может задать вопрос пользователю
через `OperationRequest` (в референсе — `AccessDeniedMessage`) и продолжить.

Тестовая реализация `InMemoryTreeProvider` живёт в `test/fake/` и строит дерево
из литерала Dart: на ней тестируются контроллеры и команды без обращения к диску.

## 3. Асинхронные операции

Референс построен на собственных промисах (`IAsyncOperation` + `IAsyncOperationStatus`
с `onStart/onComplete/onError/onCancel/onFinish`). В Dart есть `Future` и `Stream`,
поэтому переносим не реализацию, а три свойства, которых у голого `Future` нет:
**отмена**, **прогресс** и **вопросы пользователю по ходу дела**.

```dart
enum OperationStatus { inited, pending, processing, complete, canceled, error }

class OperationProgress {
  final double? percent;     // null — неопределённый прогресс
  final String message;      // "Reading /usr/lib…", "12 of 340"
}

abstract class AsyncOperation<T> {
  OperationStatus get status;

  /// Результат. Завершается ошибкой FsError или OperationCanceled.
  Future<T> get result;

  /// Прогресс. Для быстрых операций (чтение каталога) может не отдавать ничего.
  Stream<OperationProgress> get progress;

  /// Вопросы пользователю: перезаписать? пропустить? продолжить без прав?
  /// Пустой поток у операций, которые ничего не спрашивают.
  Stream<OperationRequest> get requests;

  void cancel();
}
```

```dart
/// Запрос из середины операции. Аналог IInteraction/IMessage референса.
class OperationRequest {
  final String message;
  final List<OperationOption> options;   // Overwrite / Skip / Skip all / Cancel
  void answer(OperationOption option);
}
```

Правила:

- Каждая операция **отменяема**. Открытие каталога отменяет предыдущее незавершённое
  открытие в этой же панели (поведение референса: `cancelPreviousOperations()`).
- Результат «отменено» — не ошибка приложения: контроллер просто возвращает панель
  в прежнее состояние.
- Пакетные операции (`copy`, `move`, `remove`) — это тот же `AsyncOperation`, а не
  отдельный вид. В референсе у переноса был свой строитель (`TransferOperation` с
  `from`/`to`/`nodes`), но здесь операция начинает работу сразу после создания,
  и настраивать её потом уже нечем: всё, что нужно, передаётся аргументами.
  Очередь наружу не выставляется — о ходе работы говорит `progress`.

### Копирование и перенос

- **Копируется объект, а не то, куда он ведёт.** Ссылка копируется ссылкой: создаётся
  новая с тем же значением. Пути берутся через `entityPathOf` — `physicalPathOf` для
  ссылки вернул бы её цель, и перенос ссылки утащил бы за собой чужой каталог.
- **Каталог переносится вместе с содержимым**, рекурсивно.
- **Занятое имя — вопрос, а не решение.** `OperationRequest` предлагает перезаписать,
  перезаписать все, пропустить, пропустить все, отменить; ответ «…все» запоминается
  на всю операцию. Ответ по умолчанию — «пропустить»: молча затирать чужие файлы нельзя.
- **Ошибка на одном объекте не прекращает работу** — задаётся тот же вопрос.
- **Перенос начинается с переименования**: в пределах диска оно мгновенное. Между
  дисками (`EXDEV`) объект копируется и затем удаляется.
- **Невозможные задания отсекаются до работы**: копирование каталога внутрь самого
  себя (`FsErrorKind.targetInsideSource`) не закончилось бы никогда, а копирование
  «на себя же» бессмысленно.
- Прогресс считается по объектам задания, а не по байтам: побайтовый прогресс
  потребовал бы предварительного обхода дерева (в референсе для этого было отдельное
  окно подготовки) — это отдельная задача.

## 4. Колонки

Набор колонок настраивается пользователем: состав, порядок, ширина, видимость;
раскладка своя у каждой панели.

```dart
/// Идентификатор колонки. Значения сохраняются в settings.json по имени,
/// поэтому переименовывать их нельзя — только добавлять новые.
enum FsColumn {
  icon,        // иконка типа объекта; не сортируется, не скрывается
  name,        // единственная «резиновая» колонка; не скрывается
  ext,
  size,
  modified,
  created,
  accessed,
  attributes,
}
```

```dart
enum ColumnAlign { start, end }

class ColumnSpec {
  final FsColumn id;
  final double width;      // игнорируется для «резиновой» колонки
  final double minWidth;
  final bool visible;
  final bool pinned;       // нельзя скрыть/переместить: icon и name
  final ColumnAlign align;

  ColumnSpec copyWith({double? width, bool? visible});
}

class ColumnLayout {
  /// Порядок в списке = порядок на экране слева направо.
  final List<ColumnSpec> columns;

  List<ColumnSpec> get visibleColumns;

  ColumnLayout moveColumn(int from, int to);
  ColumnLayout resize(FsColumn id, double width);
  ColumnLayout toggleVisible(FsColumn id);

  static ColumnLayout get defaults;
}
```

Раскладка по умолчанию — как в макете и в референсе (`FilesPanel`: Name 100%, Ext, Size, Modified):

| Колонка | Ширина | Выравнивание | Видима по умолчанию |
|---------|--------|--------------|---------------------|
| `icon` | 24 | — | да |
| `name` | резиновая, min 80 | слева | да |
| `ext` | 40 | справа | да |
| `size` | 60 | справа | да |
| `modified` | 78 | справа | да |
| `created` | 78 | справа | нет |
| `accessed` | 78 | справа | нет |
| `attributes` | 84 | слева | нет |

Расчёт ширин при отрисовке: сумма фиксированных ширин видимых колонок вычитается из
ширины панели, остаток отдаётся `name`; если остаток меньше её `minWidth`, включается
горизонтальная прокрутка таблицы.

## 5. Сортировка

```dart
enum SortDirection { ascending, descending }

class SortSpec {
  final FsColumn column;
  final SortDirection direction;

  /// Каталоги (и ссылки на каталоги) всегда выше файлов.
  final bool foldersFirst;

  /// Тот же столбец — смена направления; другой — он же по возрастанию.
  SortSpec toggled(FsColumn column);
}

/// Чистая функция, без обращения к ФС.
int Function(FsNode, FsNode) comparatorFor(SortSpec spec);
```

Порядок сравнения (правила 1–2 взяты из `nodesCompareFunction` референса и не зависят
от направления сортировки):

1. `ParentDirNode` — всегда первый.
2. Если `foldersFirst` — каталоги перед файлами; ссылка на каталог считается
   каталогом (тип цели известен из `LinkNode.targetType` сразу после чтения).
3. Сравнение по колонке:
   - `name`, `ext`, `attributes` — регистронезависимо, «естественный» порядок чисел
     (`file2` перед `file10`), функция `naturalCompare`;
   - `size` — числовое; `-1` (неизвестный размер) меньше любого значения;
   - даты — по `microsecondsSinceEpoch`; отсутствующая дата меньше любой;
   - `icon` — по `FileType.index`.
4. При равенстве — доводчик по `name` по возрастанию, чтобы порядок не «плавал»
   между перечитываниями.
5. `direction` переворачивает результат шагов 3–4, но не шагов 1–2.

Сортировка выполняется в `PanelController` после чтения каталога и при смене `SortSpec`;
результат кэшируется, при отрисовке список не пересортировывается.

## 6. Настройки

```dart
class PanelSettings {
  final String path;           // полная строка пути, включая схему провайдера
  final ColumnLayout columns;
  final SortSpec sort;
  final bool showHidden;

  Map<String, Object?> toJson();
  factory PanelSettings.fromJson(Map<String, Object?> json);
}

class AppSettings {
  final PanelSettings left;
  final PanelSettings right;
  final int activePanel;       // 0 — левая, 1 — правая
  final double splitRatio;     // доля ширины окна под левой панелью, 0.2…0.8
  final AppThemeMode themeMode;   // system | light | dark; собственный тип,
                                  // чтобы модели не зависели от Flutter

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  final WindowGeometry? window;

  static AppSettings get defaults;   // обе панели — домашний каталог, split 0.5
}

class WindowGeometry {
  final double left, top, width, height;

  /// Окно развёрнуто. Само положение и размер при этом хранятся те, к которым
  /// окно вернётся после сворачивания.
  final bool maximized;
}
```

Файл: `~/.flex-commander/settings.json` (в референсе — `~/.flexnavigator/settings.json`;
на macOS допустимо и `Application Support`, но точка-каталог в домашней папке удобнее
для правки руками и одинаково работает на всех платформах).

```json
{
  "version": 1,
  "activePanel": 0,
  "splitRatio": 0.5,
  "themeMode": "system",
  "window": { "left": 120, "top": 80, "width": 900, "height": 640, "maximized": false },
  "panels": [
    {
      "path": "fs:/Users/koldoon/Developer",
      "showHidden": false,
      "sort": { "column": "name", "direction": "ascending", "foldersFirst": true },
      "columns": [
        { "id": "icon", "width": 24, "visible": true },
        { "id": "name", "width": 0, "visible": true },
        { "id": "ext", "width": 40, "visible": true },
        { "id": "size", "width": 60, "visible": true },
        { "id": "modified", "width": 78, "visible": true }
      ]
    }
  ]
}
```

Разбор устойчив к мусору: неизвестные `id` колонок и лишние поля игнорируются,
отсутствующие берутся из умолчаний, при ошибке разбора применяется `AppSettings.defaults`
и пишется предупреждение в лог. Недоступный при старте `path` заменяется на домашний
каталог (референс делал то же самое в `StartupCommand`).

## 7. Форматирование

Чистые функции в `view/format/`, покрытые unit-тестами.

```dart
/// 126 -> "126", 92262 -> "90.1K", 15616819 -> "14.9M", -1 -> "" (размер неизвестен).
/// Основание 1024; один знак после запятой начиная с K; для байт — без суффикса.
String formatSize(int bytes);

/// 2018-02-19 -> "19-02-2018" (формат макета).
String formatDate(DateTime value);

/// Для строки состояния: "1.2 GB of 4.0 GB free".
String formatBytesLong(int bytes);
```

Формат даты вынести в константу темы, чтобы позже сделать настраиваемым.
Локализация в MVP не требуется — интерфейс английский, как в макете и в референсе.
