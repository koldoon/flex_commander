# Управление состоянием

Всё изменяемое состояние приложения живёт в двух контроллерах — `AppController`
и `PanelController` — и в реестре команд. Виджеты состояния не хранят
(кроме позиции скролла и локальных анимаций).

## 0. Слой интерфейсов — API приложения

Прежде чем говорить о контроллерах: то, что они реализуют, описано отдельно,
в `model/app/`. Это и есть API, против которого пишутся команды.

| Интерфейс | Реализация | Аналог в референсе |
|---|---|---|
| `Application` | `AppController` | `IApplication` / `ApplicationImpl` |
| `Panel` | `PanelController` | `IPanel` / `FilesPanel` |
| `PanelSelection` | `SelectionController` | `IPanelSelection` / `PanelSelection` |
| `TreeProvider` | `LocalTreeProvider` | `ITreeProvider` |
| `AsyncOperation` | `TaskOperation` | `IAsyncOperation` |

Зачем разделение:

- **Команда видит только интерфейс.** `CommandContext` отдаёт `Application` и `Panel`,
  а не контроллеры, поэтому реализацию можно переписать, не трогая ни одной команды.
  Это же станет контрактом для команд, которые появятся на следующих этапах.
- **Интерфейсы лежат в нижнем слое.** `model/app/` не знает ни о Flutter, ни о
  контроллерах; зависимости идут снизу вверх, а не наоборот.
- **`ChangeNotifier` остаётся в реализации.** Подписка на изменения нужна виджетам,
  а не командам, поэтому в интерфейсах её нет. Виджеты получают контроллеры
  (`AppScope`, `PanelScope`) и подписываются на них напрямую; типы полей `left`,
  `right` и `selection` в реализациях уточнены до конкретных классов.
- **Контейнер отдаёт и то, и другое.** `get<Application>()` возвращает тот же
  экземпляр, что и `get<AppController>()`.

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
  /// false — путь недоступен или это не каталог; куда открывать панель в этом
  /// случае, решает вызывающий код. Панель занята уже на разборе пути:
  /// он тоже идёт через провайдера и может быть небыстрым.
  Future<bool> openPath(String path);

  /// Войти в объект под курсором: каталог — открыть, ссылку — разрешить и открыть
  /// цель, «..» — подняться наверх. Возвращает узел, в который войти нельзя
  /// (обычный файл) — открывать его системой будет команда; null, если переход
  /// выполнен.
  Future<FsNode?> enterCurrent();

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

Тот же механизм используется при `goUp()`: панель запоминает имя объекта, через который
вошла, и ставит на него курсор (реализовано в референсе в `openParentDirectory()`).
Если каталог открыт через ссылку, этим объектом будет сама ссылка: `goUp()` поднимается
по цепочке узлов, перешагивая через неё, и возвращает пользователя туда, откуда он
пришёл, а не в физического родителя цели.

### Память курсора по каталогам

`PanelController` держит `Map<String, String> _cursorMemory` (путь каталога → имя объекта
под курсором), ограниченную сотней последних записей. Возврат в ранее посещённый каталог
восстанавливает курсор. Карта не сохраняется между запусками.

Подъём наверх важнее памяти курсора: после `goUp()` курсор всегда встаёт на покинутый
каталог, даже если в родительском каталоге пользователь оставлял его в другом месте.

## 4. `AppController`

```dart
class AppController extends ChangeNotifier {
  AppController({
    required PanelController left,
    required PanelController right,
    required SettingsStore store,
    required AppSettings settings,
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

  /// Геометрия окна. Приходит от WindowService при перемещении и изменении
  /// размера; у развёрнутого окна запоминаются размеры до разворота.
  WindowGeometry? get windowGeometry;
  void setWindowGeometry(WindowGeometry? geometry);

  /// Реестр команд появляется на этапе клавиатуры (см. keyboard.md).
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

/// Привязка живёт в реестре, а не в команде: так клавиши можно переназначать,
/// не трогая код команд, и хранить привязки в настройках.
class KeyBinding {
  final KeyCombination keys;

  /// Идентификатор команды, а не сама команда: в настройках хранятся только
  /// идентификаторы, и подмена реализации команды привязки не затрагивает.
  final String commandId;

  /// Необязательный фильтр по имени объекта под курсором.
  /// Позволяет повесить на Enter разные команды для *.app, *.zip и обычных файлов —
  /// приём референса (BindingProperties.nodeValue).
  final RegExp? nameMatch;
}

// Параметров у привязки нет намеренно: команда не должна зависеть от того,
// чем её вызвали — см. keyboard.md, «Команда не знает, чем её вызвали».


abstract class AppCommand {
  /// Стабильный идентификатор для настроек, логов и поиска команды в коде:
  /// "panel.open", "file.copy". Пользователю не показывается.
  String get id;

  /// Название команды для пользователя: подпись кнопки внизу окна и строка
  /// в списке команд. Именно label видно в интерфейсе — не id и не имя класса.
  /// Привязок клавиш у команды нет: ими заведует реестр.
  String get label;

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

/// Всё, на что опирается команда: активная панель и выбранные объекты.
class CommandContext {
  final AppController app;
  final PanelController panel;      // активная панель — источник операции
  final FsNode? node;               // объект под курсором
  final List<FsNode> targets;       // помеченные объекты или [node], если пометки нет

  PanelController get target => app.passivePanel;   // приёмник операции
}
```

```dart
class CommandRegistry {
  void install(AppCommand command);      // вызывает command.init(app)

  // Привязки: установка, снятие и просмотр — всё здесь.
  void bind(KeyBinding binding);
  void unbind(String commandId);
  List<KeyBinding> get bindings;               // в порядке приоритета
  List<KeyBinding> bindingsOf(String commandId);

  /// Находит первую подходящую команду и выполняет её.
  /// Возвращает false, если ничего не подошло — тогда событие клавиатуры
  /// уходит дальше по дереву Flutter.
  bool dispatch(KeyCombination keys, AppController app);

  /// Какая команда закреплена за комбинацией клавиш прямо сейчас.
  /// Этим пользуется нижняя панель: у команд своего места в интерфейсе нет.
  AppCommand? commandFor(KeyCombination keys);

  Iterable<AppCommand> get installed;
}
```

Алгоритм `dispatch` (повторяет `ApplicationImpl.processKeyboardCombination`):

1. перебрать **привязки** в порядке их установки — он и задаёт приоритет;
2. отобрать те, где совпала комбинация, и найти команду по `commandId`;
3. если у привязки задан `nameMatch`, проверить имя объекта под курсором;
4. собрать `CommandContext` — активная панель и выбранные объекты, ничего больше;
5. если `isExecutable(context)` — выполнить и остановиться.

Порядок привязок задаёт приоритет, поэтому специализированные («Enter на архиве»)
ставятся раньше общих («Enter»).

Правило: «одна и та же логика — одна команда». Кнопка F5 внизу окна, пункт меню
и нажатие F5 вызывают один и тот же `AppCommand`; кнопка неактивна ровно тогда,
когда `isExecutable()` возвращает false.

Список команд MVP и их привязки — в [`keyboard.md`](keyboard.md).

### Как команда общается с пользователем

Файловой операции почти всегда нужно что-то спросить: имя нового каталога,
подтверждение удаления, что делать с существующим файлом. Команда не может
показать диалог сама — она не знает о виджетах и выполняется вне их дерева.

Для этого в API приложения есть `UserInteraction` (в референсе эту роль играл
`IApplication.popupManager`):

```dart
final name = await context.app.dialogs.promptText(title: 'Create directory', confirmLabel: 'Create');
if (name == null) return;                      // пользователь отказался
...
await context.app.dialogs.showError(title: 'Cannot create directory', message: error.message);
```

- Реализация `DialogUserInteraction` живёт в слое представления и владеет ключом
  навигатора: команды выполняются вне дерева виджетов, и другого доступа к нему
  у них нет.
- В тестах подставляется `FakeUserInteraction` — она запоминает вопросы и отвечает
  заранее заданным, поэтому логика команды проверяется без единого виджета.
- Там, где интерфейса нет вовсе, работает `SilentUserInteraction`: она отвечает
  отказом, и команда просто не выполняется.

Вопросы **по ходу** длительной операции (перезаписать? пропустить?) — это другое:
для них у `AsyncOperation` есть `OperationRequest`, см. [`models.md`](models.md).

### Файловые операции

Изменение дерева живёт за интерфейсом `TreeEditor`, отдельным от `TreeProvider`:
провайдер может уметь только читать (архив, открытый на просмотр). Панель отдаёт
его готовым — `panel.editor`, null у провайдера без записи, и с этой проверки
начинается любая файловая команда.

Порядок в `MakeDirectoryCommand` — образец для остальных операций:

1. `isExecutable`: панель не занята, каталог открыт, `panel.editor != null`;
2. спросить пользователя через `app.dialogs`;
3. выполнить операцию редактора и дождаться результата;
4. перечитать панель и поставить курсор на созданный объект;
5. поймать `FsError` и показать его текст пользователем.

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
- Сохранение — при завершении приложения и дополнительно с задержкой 1 с после
  изменений, чтобы не терять настройки при падении.
- Момент выхода ловится через `AppLifecycleListener.onExitRequested`: система
  спрашивает разрешение закрыться, и это единственное место, где настройки ещё можно
  дописать. Обработчик вызывает `AppController.shutdown()` и разрешает выход.
- Панели уведомляют обо всём подряд, включая движение курсора, поэтому перед записью
  `AppController` сравнивает сериализованный снимок настроек с последним сохранённым:
  запись происходит, только если изменилось то, что действительно хранится.
- Запись атомарная: временный файл рядом + `rename`.
- Ошибки записи не должны мешать работе: логируются и игнорируются.

## 8. Контейнер зависимостей

Граф служб приложения собран в одном месте — `AppContext` (контейнер `dicom`):

```dart
class AppContext extends DI {
  AppContext({TreeProvider? provider, SettingsStore? store, WindowService? window}) {
    bind<Logger>(to: (c) => Logecom.createLogger(c.plan[c.plan.length - 2]), dynamic: true);
    bind<TreeProvider>(to: (c) => provider ?? LocalTreeProvider());
    bind<WindowService>(to: (c) => window ?? PluginWindowService());
    bind<SystemOpener>(to: (c) => openWithSystem);
    bind<SettingsStore>(to: (c) => store ?? SettingsStore.forHome(...));
    bind<PanelControllerFactory>(to: (c) => PanelControllerFactory(provider: c.get<TreeProvider>()));
    bind<CommandRegistry>(to: (c) => CommandRegistry(defaultCommands(opener: c.get<SystemOpener>()), defaultKeyBindings()));
    bind<AppController>(to: (c) => AppController(...));
  }
}
```

Что из этого следует:

- **Зависимости приходят параметрами конструктора.** Ни один класс не достаёт себе
  зависимость сам; `inject<T>()` существует, но пользоваться им должна только точка
  сборки — иначе контейнер превратится в глобальную переменную.
- **Создание ленивое.** Служба появляется при первом обращении. Это не теория:
  `PluginWindowService` в конструкторе обращается к плагину окна, которого в тестах
  нет, — и это не мешает собрать контекст в тесте.
- **Подмена — через параметры конструктора.** Повторная привязка того же типа
  в `dicom` не заменяет прежнюю, а добавляется к ней (это механизм множественных
  зависимостей), поэтому для подстановки заглушек предусмотрены параметры.
- **Тип зависимости берётся из места вызова.** У необязательного параметра он
  nullable, поэтому `c.get<CommandRegistry>()` пишется явно: иначе контейнер будет
  искать привязку к `CommandRegistry?` и не найдёт её.
- **Асинхронные зависимости связываются после чтения.** Фабрики контейнера
  синхронные, а настройки читаются с диска, поэтому `AppContext.init()` сначала
  берёт из контейнера `SettingsStore`, дожидается `load()` и только потом связывает
  готовый `AppSettings`. К этому моменту его ещё никто не запрашивал.
- **Две панели — через фабрику.** Контейнер не различает два экземпляра одного
  типа, поэтому он отдаёт `PanelControllerFactory`, а какая панель левая, решает
  `AppController`.

Логгер связан как `dynamic`: он создаётся заново на каждый запрос, а категорию берёт
из дерева зависимостей (`c.plan`) — в логах сразу видно, какой класс написал строку.

## 9. Тестирование

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
