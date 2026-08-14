# Управление состоянием

Всё изменяемое состояние приложения живёт в двух контроллерах — `AppController`
и `PanelController` — и в реестре команд. Виджеты состояния не хранят
(кроме позиции скролла и локальных анимаций).

Роли повторяют референс: `IApplication` → `AppController`, `IPanel` → `PanelController`,
`IPanelSelection` → `PanelSelection`, `ICommand` + `BindingProperties` → `AppCommand` + `KeyBinding`.

## 1. Механизм

| Задача | Решение |
|---|---|
| Уведомление об изменениях | `ChangeNotifier` |
| Доставка контроллеров в дерево | `InheritedNotifier` (`AppScope`) |
| Подписка виджета | `AnimatedBuilder` / `ListenableBuilder` на нужный контроллер |
| Внедрение зависимостей | конструкторы; сборка графа — в `main.dart` |

Внешние пакеты (`provider`, `riverpod`, `bloc`) не используются: контроллеров всего три,
их время жизни равно времени жизни приложения, а перерисовка нужна точечная.

Правило гранулярности: подписываться на **самый узкий** источник. Строка файла
подписана на `PanelSelection`, а не на весь `PanelController`, — иначе перемещение
курсора перерисовывает всю таблицу (в референсе `FileItemRenderer` тоже слушал только
`selection.change`).

## 2. `PanelSelection`

Пометка объектов, вынесенная из панели отдельным объектом — как `IPanelSelection`.

```dart
class PanelSelection extends ChangeNotifier {
  bool contains(FsNode node);
  void add(FsNode node);        // ParentDirNode игнорируется
  void remove(FsNode node);
  void toggle(FsNode node);
  void clear();

  List<FsNode> get nodes;
  int get length;

  /// Суммарный размер помеченных объектов — для строки состояния.
  int get totalSize;
}
```

Хранение — `LinkedHashSet<FsNode>` по идентичности узлов, порядок пометки сохраняется
(он же становится порядком обработки в файловых операциях).

## 3. `PanelController`

Состояние одной панели. Ничего не знает ни о второй панели, ни о виджетах.

```dart
enum PanelStatus { idle, loading, error }

class PanelController extends ChangeNotifier {
  PanelController({required TreeProvider provider, required PanelSettings settings});

  // --- каталог ---

  DirectoryNode? get directory;

  /// Отсортированное содержимое — то, что рисует таблица.
  List<FsNode> get nodes;

  PanelStatus get status;
  FsError? get error;

  /// Открыть каталог: читает содержимое и только после успеха меняет directory.
  /// Отменяет предыдущее незавершённое открытие этой панели.
  Future<void> open(DirectoryNode dir);

  /// Открыть по строке пути (используется при старте и восстановлении настроек).
  Future<void> openPath(String path);

  /// Войти в объект под курсором: каталог — открыть, ссылку — разрешить и открыть цель,
  /// файл — отдать системе (см. команду OpenNodeCommand).
  Future<void> enterCurrent();

  /// На уровень вверх; курсор встаёт на покинутый каталог.
  Future<void> goUp();

  /// Перечитать текущий каталог, сохранив курсор и пометку.
  Future<void> reload();

  // --- курсор ---

  int get cursorIndex;
  FsNode? get currentNode;

  void moveCursor(int delta);          // ±1, ±страница
  void setCursorIndex(int index);      // с клампом в границы списка
  void setCursorToName(String name);   // используется при возврате вверх и после reload

  // --- пометка ---

  PanelSelection get selection;

  // --- вид ---

  ColumnLayout get columns;
  void setColumnLayout(ColumnLayout layout);

  SortSpec get sort;
  void sortBy(FsColumn column);        // тот же столбец — смена направления

  bool get showHidden;
  void setShowHidden(bool value);

  // --- состояние панели ---

  /// Активна ли панель (в ней курсор и фокус клавиатуры).
  /// Устанавливается только через AppController.
  bool get active;

  /// Заблокирована на время длительной операции: клавиатура игнорируется,
  /// кроме Esc (поведение референса).
  bool get busy;

  /// Текст строки состояния, если его выставила команда ("Loading…").
  /// null — панель показывает информацию о текущем объекте.
  String? get statusText;
  void setStatusText(String? text);
}
```

### Поток данных при открытии каталога

```
клавиша Enter
   │
   ▼
CommandRegistry.dispatch("Enter")
   │
   ▼
OpenNodeCommand.execute()
   │  panel.busy = true; statusText = "Loading…"
   ▼
PanelController.open(dir)
   │
   ▼
dir.refresh() → TreeProvider.getDirectoryListing(dir)   [AsyncOperation, изолят]
   │
   ├─ ошибка ────────► status = error, панель остаётся на прежнем каталоге,
   │                   в строке состояния — сообщение
   ├─ отменено ──────► состояние не меняется
   └─ успех ─────────► directory = dir
                       nodes = sort(dir.nodes)
                       selection.clear()
                       cursorIndex = 0
                       busy = false; statusText = null
                       notifyListeners()
                              │
                              ▼
                     ListenableBuilder перестраивает FileTable
```

Важно: `directory` меняется **после** успешного чтения, а не до. Иначе при ошибке
доступа панель окажется в каталоге, содержимое которого показать нельзя
(референс делал именно так: `listingOperation.status.onComplete → ap.directory = dir`).

### Перечитывание каталога

После `refresh()` узлы — новые экземпляры, поэтому:

- курсор восстанавливается **по имени** прежнего текущего объекта; если объект исчез —
  курсор встаёт на ближайший индекс из старой позиции;
- пометка восстанавливается по именам ранее помеченных объектов; исчезнувшие отбрасываются;
- позиция скролла сохраняется, если курсор остался в видимой области.

Тот же механизм используется при `goUp()`: панель запоминает имя покинутого каталога
и ставит на него курсор (реализовано в референсе в `openParentDirectory()`).

### Память курсора по каталогам

`PanelController` держит `Map<String, String> _cursorMemory` (путь каталога → имя объекта
под курсором), ограниченную сотней последних записей. Возврат в ранее посещённый каталог
восстанавливает курсор. Карта не сохраняется между запусками.

## 4. `AppController`

```dart
class AppController extends ChangeNotifier {
  AppController({
    required PanelController left,
    required PanelController right,
    required CommandRegistry commands,
    required SettingsStore settings,
  });

  PanelController get left;
  PanelController get right;

  /// Активная панель — источник операций.
  PanelController get activePanel;

  /// Пассивная — приёмник операций (аналог getPassivePanel()).
  PanelController get passivePanel;

  void activate(PanelController panel);
  void toggleActivePanel();            // Tab

  double get splitRatio;
  void setSplitRatio(double value);

  CommandRegistry get commands;

  /// Старт: читает настройки, открывает каталоги обеих панелей,
  /// активирует ту, что была активной в прошлый раз.
  Future<void> start();

  /// Завершение: сохраняет настройки, останавливает незавершённые операции.
  Future<void> shutdown();
}
```

Инвариант: ровно одна панель активна в любой момент. `activate()` снимает флаг со второй.
Ветвление «если левая активна, то…» существует только внутри `AppController`
(в референсе — то же самое в `ApplicationImpl.changeActivePanel()`).

## 5. Команды

Действие пользователя — это команда, а не обработчик внутри виджета. Модель взята
из референса (`ICommand` + `IBindable` + `BindingProperties`) с поправкой на Dart.

```dart
/// Комбинация клавиш в нормализованной форме: "Enter", "Cmd-O", "Shift-F5".
/// Порядок модификаторов фиксирован: Ctrl-Alt-Shift-Cmd.
class KeyCombination {
  factory KeyCombination.fromEvent(KeyEvent event);
  factory KeyCombination.parse(String value);
  @override String toString();
}

class KeyBinding {
  final KeyCombination keys;

  /// Необязательный фильтр по имени объекта под курсором.
  /// Позволяет повесить на Enter разные команды для *.app, *.zip и обычных файлов —
  /// приём референса (BindingProperties.nodeValue).
  final RegExp? nameMatch;

  /// Параметры, с которыми команда вызывается именно по этой привязке
  /// (например Cmd-O — «открыть системой», не входя в каталог).
  final Map<String, Object?> parameters;
}

abstract class AppCommand {
  /// Стабильный идентификатор для настроек и логов: "panel.open", "file.copy".
  String get id;

  /// Подпись для нижней панели: F5 «Copy». null — команда не показывается кнопкой.
  FunctionKeySlot? get functionKey;

  List<KeyBinding> get bindings;

  /// Вызывается один раз при старте. false — команда не устанавливается
  /// (например, недоступна на этой платформе).
  bool init(AppController app);

  /// Можно ли выполнить прямо сейчас: есть ли объект под курсором,
  /// не занята ли панель, есть ли помеченные объекты.
  bool isExecutable(CommandContext context);

  Future<void> execute(CommandContext context);

  /// Вызывается при завершении приложения: сохранить настройки, закрыть соединения.
  Future<void> shutdown();
}

class CommandContext {
  final AppController app;
  final PanelController panel;      // активная панель
  final FsNode? node;               // объект под курсором
  final List<FsNode> targets;       // помеченные объекты или [node], если пометки нет
  final Map<String, Object?> parameters;
}
```

```dart
class CommandRegistry {
  void install(AppCommand command);      // вызывает command.init(app)

  /// Находит первую подходящую команду и выполняет её.
  /// Возвращает false, если ничего не подошло — тогда событие клавиатуры
  /// уходит дальше по дереву Flutter.
  bool dispatch(KeyCombination keys, AppController app);

  /// Для нижней панели: какая команда занимает слот F5 и активна ли она сейчас.
  AppCommand? commandForSlot(FunctionKeySlot slot);

  Iterable<AppCommand> get installed;
}
```

Алгоритм `dispatch` (повторяет `ApplicationImpl.processKeyboardCombination`):

1. перебрать установленные команды в порядке установки;
2. у каждой — её привязки; отобрать те, где совпала комбинация;
3. если у привязки задан `nameMatch`, проверить имя объекта под курсором;
4. собрать `CommandContext` с параметрами привязки;
5. если `isExecutable(context)` — выполнить и остановиться.

Порядок установки задаёт приоритет, поэтому специализированные команды
(«Enter на архиве») ставятся раньше общих («Enter»).

Правило: «одна и та же логика — одна команда». Кнопка F5 внизу окна, пункт меню
и нажатие F5 вызывают один и тот же `AppCommand`; кнопка неактивна ровно тогда,
когда `isExecutable()` возвращает false.

Список команд MVP и их привязки — в [`keyboard.md`](keyboard.md).

## 6. Доступ из виджетов

```dart
class AppScope extends InheritedNotifier<AppController> {
  static AppController of(BuildContext context);
  static PanelController panelOf(BuildContext context);   // ближайшая панель
}
```

Панель отдаётся вниз отдельным `InheritedWidget`-ом (`PanelScope`), чтобы виджеты
внутри панели не знали, левая она или правая: одни и те же `FileTable`, `FileTableRow`
и `PanelStatusBar` работают в обеих.

Типовое использование:

```dart
ListenableBuilder(
  listenable: panel,
  builder: (context, _) => FileTable(nodes: panel.nodes, ...),
)
```

## 7. Сохранение настроек

```dart
class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
```

- Загрузка — один раз при старте, до первого кадра (в `main()`, с показом окна после).
- Сохранение — при завершении приложения (`SaveSettingsCommand.shutdown()`, как в
  референсе) и дополнительно с задержкой 1 с после изменений раскладки колонок,
  сортировки, `splitRatio` и текущего каталога, чтобы не терять настройки при падении.
- Запись атомарная: временный файл рядом + `rename`.
- Ошибки записи не должны мешать работе: логируются и игнорируются.

## 8. Тестирование

| Что | Как |
|---|---|
| Компараторы, форматтеры, разбор путей, разбор режима доступа | чистые unit-тесты |
| `PanelController` (открытие, курсор, пометка, восстановление после reload) | unit-тесты на `InMemoryTreeProvider`, без Flutter |
| `CommandRegistry.dispatch` (приоритеты, `nameMatch`, `isExecutable`) | unit-тесты с фейковыми командами |
| `SettingsStore` (мусор в JSON, отсутствующие поля, недоступный путь) | unit-тесты на временном каталоге |
| Клавиатура и фокус целиком | widget-тесты: `sendKeyEvent` + проверка курсора и активной панели |
| Вёрстка панели | golden-тесты по макету на фиксированном размере окна |

Обязательное требование к контроллерам: они конструируются без Flutter и без реальной ФС,
поэтому большая часть логики тестируется быстрыми unit-тестами.
