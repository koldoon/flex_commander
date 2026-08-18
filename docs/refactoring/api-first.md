# API-First: рефакторинг архитектуры Flex Commander

## Контекст

Сейчас всё приложение — один пакет `flex_commander`. Любая новая возможность требует
правки ядра: `lib/app_context.dart` поимённо знает `LocalTreeProvider` (:36),
`ZipTreeProvider` (:44), `TreeTransferEngine` (:49), `PluginWindowService` (:50) и
`defaultCommandRegistry` (:75). Слои местами перевёрнуты: `lib/state/commands/*`
импортирует `lib/view/*` (`help_command.dart:6,7`, `file_commands.dart:5,6`,
`transfer_commands.dart:6,7`), а `AppCommand` возвращает `Widget`. Тема статична
(`AppTheme.theme` — `static final`, `app.dart:55`), иконки не темизируются вовсе,
настройки модуля хранить негде (`AppSettings.toMap` пересобирает фиксированный набор
ключей и теряет чужое), содержимое панели жёстко прибито к `FileTable`
(`panel_view.dart:65`).

Цель — вынести **чистый API** (модели, интерфейсы, командный фреймворк, UI-kit) в
отдельный пакет и сделать всякую функциональность модулем `FcModule`, зависящим только
от этого API. В ядре остаётся базовое: оболочка окна, панели, клавиатура, сборка.
Любое действие выражается командой; командный фреймворк портируется с
[Spicelib-Commands](https://github.com/spicefactory/Spicelib-Commands) (исходники локально:
`~/Developer/Flex Projects/Spicelib-Commands`).

**Решения, принятые с пользователем:**

1. Сразу **pub workspaces**: корневой `pubspec.yaml` получает `workspace:`, пакеты живут
   в `dependency/`, каждый — с `resolution: workspace`. Dart 3.7 это поддерживает.
2. **`Command.getDialog()` остаётся единственным путём** для окон команд — потому что
   решение о показе принадлежит ядру. Задел: ядро может спрятать окно работающей команды
   и показать её статус в общем месте с остальными фоновыми процессами. `api.showDialog()`
   намеренно **не** вводится.
3. Порт Spicelib **без `CommandFlow`**: `Command`/`CommandExecutor`, `CommandProxy`
   (timeout, result/error/cancel), `CommandGroup` (sequence + parallel), `CommandData`,
   `CommandLifecycle`, построители `Commands.create/wrap/asSequence/inParallel`.
   `CommandFlow`/`CommandLink`/`LinkConditions` — отложены до реального сценария.
4. Модули этого захода: **zip_archiver, default_theme, navigation, file_ops**. Первая тема —
   `default`: в модуль выносится нынешнее (тёмное) оформление как есть, а не новая светлая.
   Так модуль темы проверяется голденами пиксель-в-пиксель, а `light` появится потом
   отдельным пакетом по уже отлаженному контракту.

## Целевая раскладка

```
flex_commander/                 # корень воркспейса + ядро приложения
dependency/api/                 # fc_api          (flutter)
dependency/test_kit/            # fc_test_kit     (dev-only, фейки для тестов)
dependency/navigation/          # fc_navigation
dependency/file_ops/            # fc_file_ops
dependency/zip_archiver/        # fc_zip_archiver
dependency/default_theme/       # fc_default_theme
```

`fc_api` обязан быть Flutter-пакетом (`Widget getDialog`, `ThemeExtension`, `Listenable`,
UI-kit). Отдельный чистый Dart-подпакет **не выделяем**: раскладка внутри
(`lib/src/{app,tree,async,panel,settings,commands/framework,format}` — чистые;
`lib/src/{ui,commands}` — Flutter) готовит выделение одним `git mv`, а чистоту стережёт
доктринальный тест (grep `dart:io`/`package:flutter` по чистым каталогам).

### Что куда уезжает

**→ `fc_api`:** `model/app/*` (+`Listenable`), `model/tree/{fs_node,node_path,tree_provider,
provider_registry,file_type,file_attributes}` (без `dart:io`-фабрик), `model/tree/transfer/
transfer_engine.dart`, `model/async/*`, `model/panel/*` (+`extension FsColumnTitle`),
`model/settings/{app_settings,window_geometry}`, `core/serialization.dart`,
`model/os/window_service.dart` + `typedef SystemOpener`, `state/commands/{app_command,
command_registry,key_combination,async_command_base}`, `state/throttle.dart`,
`view/dialogs/command_dialog.dart`, `view/theme/*`, `view/format/*`,
`view/dialogs/help_table.dart` → `FcKeyValueTable`. Новое: `module/`, `commands/framework/`,
`background/`, `panel/viewport.dart`, `StagingArea`.

**Остаётся в ядре:** `app.dart`, `main.dart`, `bootstrap/` (бывший `app_context.dart`),
`state/{app_controller,panel_controller,selection_controller,app_scope}`, `view/*`
(оболочка + `FileTable` как штатный viewport), `model/settings/settings_store.dart`,
и `lib/modules/local_fs/` — `LocalTreeProvider`, `local_listing`, `dart:io`-фабрики
`FileType.fromEntityType`/`FileAttributes.fromStat`, `LocalStagingArea`, `openWithSystem`,
`plugin_window_service`. Локальная ФС оформляется как `FcModule`, но физически живёт в
ядре: без неё не прочитать сами настройки (`SettingsStore.forHome(provider.homePath)`).
Каталог выложен так, чтобы вынос был `git mv` без правок кода.

**→ модули:** `navigation_commands`/`selection_commands`/`layout_commands` → `fc_navigation`;
`file_commands`/`transfer_commands` → `fc_file_ops`; `model/tree/zip/*` → `fc_zip_archiver`;
нынешняя палитра (`FcColors`/`FcMetrics`/`FcIcons` — значения по умолчанию) + стартовая
команда → `fc_default_theme`; `test/fake/*` → **`lib/`**
пакета `fc_test_kit` (Dart не умеет импортировать `test/` чужого пакета — без этого не
переедет ни один командный тест).

`LocalCopySession` расщепляется: контракт `StagingArea`/`StagedDirectory` в api,
реализация `LocalStagingArea` в ядре — иначе `zip_tree_provider.dart:10` тянет `dart:io`
из чужого поддерева. Тот же контракт понадобится rar/ssh/ftp.

## Формы нового API

```dart
abstract interface class FcModule {
  String get id;                      // 'fc.zip_archiver' — namespace настроек, адрес в логах
  String get title;
  void install(FcRegistrar registrar); // один раз при сборке, ДО появления Application
}

abstract interface class FcModuleLifecycle { Future<void> dispose(); }

abstract interface class FcRegistrar {
  SettingsScope get settings;
  void rootProvider(TreeProvider Function(FcServices c) factory);
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}});
  void command(AppCommandFactory factory);
  void binding(KeyBinding binding);          // порядок вызовов = приоритет
  void startup(AppCommandFactory factory);   // выполняется один раз при запуске
  void theme(FcThemeSpec spec);
  void viewport(String kind, PanelViewportBuilder builder);
  void service<T extends Object>(T Function(FcServices c) factory);
}

abstract interface class FcServices { T resolve<T>(); List<T> resolveAll<T>(); }
abstract interface class FcContext implements FcServices { Application get app; }
typedef AppCommandFactory = AppCommand Function(FcContext context);
```

Модуль получает **регистратор**, а не контейнер: `dicom.get<T>()` бросает при двух
привязках, то есть переопределить тип ядра модуль физически не может — отдавать контейнер
наружу значит приглашать к ошибке. Разделение `FcServices`/`FcContext` типом запрещает
обращаться к `app` там, где приложения ещё нет; попутно это чинит нынешнюю петлю
`defaultCommandRegistry()` с `late final registry` для `HelpCommand`.

Отдельного `start()` у модуля нет: стартовая работа — это стартовая **команда**.

**Сборка** выражена самим фреймворком — она же первая его проверка боем:

```dart
Future<AppRuntime> initModules(List<FcModule> modules, {AppOverrides overrides});
// AppBootstrapCommand = Commands.asSequence()
//   .add(InstallModulesCommand())      // FcModule.install → Registrations
//   .add(LoadSettingsCommand())        // AppSettings + ModuleSettings
//   .add(BuildContainerCommand())      // dicom: ProviderRegistry, CommandRegistry, AppController
//   .add(RunStartupCommandsCommand())  // registrar.startup(...) последовательно
```

**Командный фреймворк** (чистый Dart). `AsyncCommand` из референса в Dart исчезает:
асинхронность уже выражена `Future`, завершение — завершением future, ошибка — броском,
отмена — `cancel()` + `CommandCanceled`. Прогресс — не дело фреймворка, он в
`AsyncOperation.progress`/`TaskStatus`.

```dart
abstract interface class Command { Future<void> execute(); }
abstract interface class ResultCommand<T> implements Command { T? get result; }
abstract interface class CancellableCommand implements Command { void cancel(); }
abstract interface class SuspendableCommand implements Command { bool get suspended; void suspend(); void resume(); }
class CommandCanceled implements Exception { const CommandCanceled([this.command]); final Command? command; }
class CommandResult { final Command command; final Object? value; final bool complete; final Object? error; }
class CommandData {                       // отражения в Dart нет: «тип» — параметр типа, поиск по is
  CommandData({CommandData? parent});
  void add(Object value);
  T? getObject<T extends Object>();
  List<T> getAllObjects<T extends Object>();
}
abstract interface class CommandLifecycle {
  Command createInstance(CommandFactory factory, CommandData data);
  void beforeExecution(Command command, CommandData data);
  void afterCompletion(Command command, CommandResult result);
}
abstract interface class CommandExecutor implements CancellableCommand, SuspendableCommand {
  bool get cancellable; bool get suspendable;
  void prepare(CommandLifecycle lifecycle, CommandData data);
}
class CommandProxy implements CommandExecutor {}
abstract class CommandGroup implements CommandExecutor { void addCommand(Command command); }
class CommandSequence extends CommandGroup {}
class ParallelCommands extends CommandGroup {}

abstract final class Commands {
  static CommandProxyBuilder wrap(Command command);
  static CommandProxyBuilder create(CommandFactory factory);
  static CommandProxyBuilder of(Future<void> Function() body);   // аналог «light command»
  static CommandProxyBuilder delay(Duration duration);
  static CommandGroupBuilder asSequence();
  static CommandGroupBuilder inParallel();
}
// Builder: description/timeout/data/lifecycle/result/error/cancel[/lastResult/allResults/
//          skipErrors/skipCancellations] → build() | execute()
```

**Стыковка со старым слоем — один класс, два интерфейса:**
`abstract class AppCommand extends ChangeNotifier implements Command`. Сигнатура
`Future<void> execute()` уже совпадает — все 28 существующих команд не меняются, но сразу
становятся пригодными к `Commands.asSequence().add(copy).add(reload)` (будущие макросы и
палитра команд). Фреймворк не знает про `id`/`label`/`getDialog`/`CommandContext`, реестр
не знает про группы и таймауты. Единственная точка стыковки —
`CommandRegistry implements CommandService, CommandLifecycle`: `createInstance` = фабрика +
`attachRun` + `contextFor`, `beforeExecution` = учёт окна, `afterCompletion` = закрытие
окна и маршрутизация ошибки. Попутно чинятся три дефекта: `_factoryFor` (:235) перестаёт
линейно инстанцировать все фабрики и течь `ChangeNotifier`'ами (индекс по id при
установке); `run()` (:178) перестаёт звать `execute()` без `await` и без `catch`;
`AsyncCommandBase._completion` (:170) завершается в `finally`, а не только в `submit()`.

**Фоновые работы** — право ядра спрятать окно:

```dart
abstract interface class TaskStatus implements Listenable {
  String get title; String get message; double? get progress;
  bool get isRunning; bool get canCancel; void cancel(); Future<void> get completion;
}
abstract interface class BackgroundTasks implements Listenable {
  List<TaskStatus> get tasks;
  void sendToBackground(String runId);
  void bringToFront(String runId);
  bool isInBackground(String runId);
}
// AppCommand += bool get canRunInBackground => false;  TaskStatus? get status => null;
```

`AsyncCommandBase` реализует `TaskStatus` почти даром (`progress`, `progressMessage`,
`isRunning`, `cancel()`, `completion` уже есть). Следствие: правило «нет окна → отвечать
`defaultOption`» (`async_command_base.dart:54-61`) меняется на «нет окна **и** нет фоновой
поверхности»; в фоне вопрос поднимает окно через `bringToFront`.

**Наблюдаемость, тема, настройки, viewport:**

```dart
abstract interface class Application implements Listenable {
  CommandService get commands; BackgroundTasks get background; ThemeService get theme;
  SettingsScope moduleSettings(String namespace);
  /* … прежние члены */
}
abstract interface class Panel implements Listenable {
  String get contentKind;                       // 'files' — таблица ядра
  String? get headerText; void setHeaderText(String? text);
  /* … прежние ~40 членов */
}
abstract interface class PanelSelection implements Listenable { /* … */ }

class FcThemeSpec { final String id, title; final Brightness brightness;
  final FcColors colors; final FcMetrics metrics; final FcIcons icons; final FcFonts fonts; }
abstract interface class ThemeService implements Listenable {
  List<FcThemeSpec> get available; FcThemeSpec get current; void use(String id);
}

abstract interface class SettingsScope {
  T section<T extends Serializable>(T Function() create);  // умолчания задаёт create
  void save();
}
class ModuleSettings implements Serializable { SettingsScope scope(String namespace); }
// AppSettings += final ModuleSettings modules;  toMap пишет разобранное И нетронутым всё,
// чего никто не разбирал: отключённый модуль не теряет свои настройки.

abstract interface class PanelContent { String get contentKind; }  // интерфейс, не флаг
typedef PanelViewportBuilder = Widget Function(BuildContext context, Panel panel);
abstract interface class PanelViewports {
  void register(String kind, PanelViewportBuilder builder);
  PanelViewportBuilder builderFor(String kind);   // fallback — таблица файлов
}
```

`AppController`/`PanelController`/`SelectionController` уже `ChangeNotifier` — `Listenable`
в контрактах выполняется без правок реализации, а виджеты перестают требовать конкретные
типы (сужения в `app_controller.dart:47,50,73,77` и `panel_controller.dart:109` остаются,
но перестают быть обязательными).

## Фазы

Каждая фаза самостоятельна: после неё `flutter analyze` чист, `flutter test` зелёный,
приложение запускается. Сначала — рискованные изменения контрактов внутри одного пакета,
потом расщепление, в конце — механический вынос модулей.

**Ф0. Воркспейс + `fc_test_kit` + уборка.** Корневой `workspace: [dependency/test_kit]`;
`test/fake/*` → `dependency/test_kit/lib/`; в 29 тестах `import '../fake/…'` →
`package:fc_test_kit/fc_test_kit.dart`. Удалить `AppContext.instance` (:116) и
`inject<T>()` (:120) — ноль вызовов. Удалить `test/view/failures/*`.
*Идёт первой и ничем не заменяется: без фейков в `lib/` ни один командный тест не переедет.*

**Ф1. Наблюдаемость и API ядра.** `Listenable` в `Application`/`Panel`/`PanelSelection`;
`CommandService get commands` в `Application`; `headerText` в `Panel`; виджеты переводятся
на интерфейсы. Убрать конкретные умолчания: `PanelController({TreeEditor editor})` без
`= const TreeTransferEngine()` (:27,:66), обязательный `registry` (:68), обязательный
`commands` в `AppController` (:13,:34). `function_bar.dart` подписывается ещё и на
`app.commands` — иначе команды модуля не появятся на кнопках. Тесты: 22 места
конструирования переводятся на `testApp(...)`/`testPanel(...)` из `fc_test_kit`.

**Ф2. Командный фреймворк.** Порт Spicelib в `lib/model/commands/framework/` (в Ф4 уедет
в api); `AppCommand implements Command`; `CommandRegistry implements CommandLifecycle,
CommandService` + три починки из раздела выше. Новые тесты
`test/commands/{sequence,parallel,proxy,data,lifecycle}_test.dart`.
*Риск: `run()` больше не глотает исключения — отдельный полный прогон сразу после фазы.*

**Ф3. `fc_api`: чистая часть.** Создать пакет, механически перенести модель, async,
форматтеры, сериализацию. `FileType.fromEntityType`/`FileAttributes.fromStat` вырезать в
`lib/modules/local_fs/local_mapping.dart` ядра. Ввести `StagingArea` + `LocalStagingArea`,
переключить `zip_tree_provider.dart:10`. `ProviderRegistry({TreeProvider? root})` +
`setRoot()`. Доктринальный тест чистоты `dependency/api/test/purity_test.dart`.
*Перенос — одним коммитом, поведенческие правки — отдельными.*

**Ф4. `fc_api`: команды, UI-kit, тема; разрыв инверсии слоёв.** Перенести
`state/commands/*`, `throttle`, `command_dialog.dart`, `view/theme/*`, `view/format/*`,
`help_table.dart`. `help_command.dart` берёт заголовок колонки из `column.title` вместо
`FileTableHeaderCell.titleOf` (:111,115,116). Добавить `FcCheckbox`, `FcLabel`,
`FcRadioGroup` (их нет нигде, `FcIcons.check` лежит неиспользованным). Починить ловушку
`FcButton`: корневой `Container(alignment: center)` без ширины растягивается в
`CrossAxisAlignment.stretch`-колонках — обернуть в `Align(widthFactor: 1)`, оставив
`CommandDialogActions` только разделитель и правое выравнивание.
*Порядок: прогнать голдены до правки кнопки, потом правка и сравнение.*

**Ф5. Тема как служба.** `FcIcons`/`FcFonts` — инстансные; `FcMetrics.scale`/`fontScale` —
поля конструктора; `FcThemeSpec`, `ThemeService` (реализация `ThemeController` в ядре);
`app.dart:52-57` строит `ThemeData` из `runtime.theme.current`, `AppTheme.theme` удаляется;
три виджета панели → `theme.icons.*`. Значения по умолчанию не меняются — голдены обязаны
совпасть пиксель-в-пиксель, это и есть проверка переноса.

**Ф6. `FcModule`, регистратор, `AppBootstrapCommand`.** `app_context.dart` превращается в
`BuildContainerCommand`, питающийся `Registrations`, а не хардкодом строк 36/44/49/50/75.
Внутренние модули ядра: `LocalFileSystem`, `AppShell` (`app.help`, `app.togglePanel`,
`app.split.center`, viewport `files`, `TreeTransferEngine` как служба). `defaultCommands()`
временно остаётся модулем `LegacyCommands`; `defaultCommandRegistry()` реализуется поверх
`initModules` и помечается `@Deprecated`. `command_registry_test.dart:364` (каждая привязка
указывает на установленную команду) переезжает в `test/app/bindings_test.dart` и проверяет
собранный набор модулей.
*Риск: порядок привязок (`Esc` дважды) теперь задаётся порядком модулей — обязателен тест
приоритета. `FcServices.resolveAll` обязан ловить бросок `dicom.getAll` и отдавать `[]`.*

**Ф7. Модуль-канарейка `dependency/navigation`.** Самый безопасный набор: без диалогов и
файловых операций. `application_view.dart:37` остаётся, но по строковому id с проверкой
возврата — приложение обязано работать без модуля навигации. Тесты
`navigation_commands_test`, `go_to_name_command_test`, `selection_size_test` → в пакет.
*Держать фазу маленькой: здесь всплывёт всё, чего не хватает в `FcContext`.*

**Ф8. Настройки модулей.** `ModuleSettings`/`SettingsScope` + бакет `modules` в
`AppSettings` со сквозным проносом незнакомых ключей; `FcRegistrar.settings` отдаёт scope с
namespace = `module.id`; `AppController._scheduleSave()` дёргается и по `scope.save()`.
Версию `AppSettings.version` не поднимаем — миграция не нужна.

**Ф9. Фоновые задачи и viewport панели.** `TaskStatus`/`BackgroundTasks`, `_background` в
реестре, `AsyncCommandBase implements TaskStatus`, `BackgroundBar` в `lib/view/background/`,
кнопка «в фон» в `CommandDialogProgress`. `PanelContent`/`PanelViewports`, `FilesViewport`,
`panel_view.dart:65` → `viewports.builderFor(panel.contentKind)`.
*Риск: новая поверхность в `Stack` вне `KeyboardHandler` — тест на то, что она не крадёт
фокус у панелей.*

**Ф10. `dependency/file_ops`.** `file.mkdir/remove/removePermanently/copy/move` + привязки
F5–F8, `Shift-Cmd-N`, `Cmd-Bsp`, `Shift-Cmd-Bsp`. Тесты в пакет; голден `copy_dialog.png`
остаётся в приложении (нужны шрифты и полная сборка).

**Ф11. `dependency/zip_archiver`.** `zip_tree_provider`, `zip_index`; `StagingArea` через
`context.resolve`; `archive` уходит из корневого `pubspec.yaml`.

**Ф12. `dependency/default_theme`.** `FcThemeSpec(id: 'default', title: 'Default')` с
нынешними `FcColors`/`FcMetrics`/`FcIcons`/`FcFonts`, `SwitchThemeCommand` (параметр
`themeId`) + стартовая `RestoreThemeCommand`, читающая `SettingsScope`. Тема переезжает
**без изменения значений** — голдены обязаны совпасть пиксель-в-пиксель, это и есть
приёмка. Тест: неизвестный `themeId` в настройках откатывается на `default`; приложение
без модуля темы запускается на встроенных умолчаниях api.
*Первый модуль, задействующий все механизмы разом (тема + настройки + стартовая команда +
команда с привязкой) — он же приёмочный тест API. Светлая тема — отдельный пакет позже, по
уже отлаженному контракту.*

**Ф13. Уборка и документация.** Удалить `defaultCommandRegistry/defaultCommands/
defaultKeyBindings` и `LegacyCommands`. Обновить `docs/*.md`: слои `view → state → model`
заменяются на `app → fc_api ← modules`; новый `docs/modules.md` — контракт `FcModule`,
порядок сборки, шаблон модуля. Доктринальные тесты: чистота api; ядро не импортирует
`fc_*`-модули нигде, кроме списка в `main.dart`; каждая привязка указывает на установленную
команду.

## Задачи

Каждая фаза заведена отдельной задачей в списке задач сессии (`TaskList`). Номер задачи —
в первой колонке; «блокируется» — задачи, которые должны быть закрыты раньше.

| # | Фаза | Статус | Блокируется |
|---|------|--------|-------------|
| 1 | Ф0. Воркспейс, `fc_test_kit`, уборка мёртвого кода | **выполнено** | — |
| 2 | Ф1. Наблюдаемость и API ядра | **выполнено** | 1 |
| 3 | Ф2. Командный фреймворк (порт Spicelib без `CommandFlow`) | **выполнено** | 2 |
| 4 | Ф3. `fc_api`: чистая часть | **выполнено** | 3 |
| 5 | Ф4. `fc_api`: команды, UI-kit, тема; разрыв инверсии слоёв | **выполнено** | 4 |
| 6 | Ф5. Тема как служба `ThemeService` | **выполнено** | 5 |
| 7 | Ф6. `FcModule`, регистратор, `AppBootstrapCommand` | **выполнено** | 5 |
| 8 | Ф7. Модуль-канарейка `dependency/navigation` | **выполнено** | 7 |
| 9 | Ф8. Настройки модулей: `ModuleSettings`/`SettingsScope` | **выполнено** | 7 |
| 10 | Ф9. Фоновые задачи и viewport панели | **выполнено** | 7 |
| 11 | Ф10. `dependency/file_ops` | **выполнено** | 5, 7 |
| 12 | Ф11. `dependency/zip_archiver` | **выполнено** | 4, 7 |
| 13 | Ф12. `dependency/default_theme` | **выполнено** | 6, 7, 9 |
| 14 | Ф13. Уборка и документация | pending | 8, 11, 12, 13 |

**Жёсткие связи порядка:** Ф0 → всё; Ф1 → Ф2; Ф3 (`StagingArea`) → Ф11; Ф4 (UI-kit в api)
→ Ф10; Ф6 → Ф7…Ф12; Ф5 + Ф6 + Ф8 → Ф12.

### Отклонения от плана по ходу работ

- **Ф1.** Командный фреймворк (`app_command`, `command_registry`, `key_combination`,
  `async_command_base`) и `throttle` переехали из `lib/state/` в `lib/model/commands/`
  и `lib/model/util/` уже сейчас: `Application.commands` иначе указывал бы из модели
  в состояние — ровно та инверсия слоёв, ради которой всё затевается. Ф4 от этого
  становится меньше: там остаётся перенос в пакет и разделение UI-kit.
- **Ф1.** `Listenable` живёт в `package:flutter/foundation.dart`, поэтому «чистые»
  каталоги `fc_api` не будут свободны от Flutter полностью. Доктринальный тест Ф3
  проверяет отсутствие `dart:io` и `package:flutter/{widgets,material,services}`;
  `foundation` разрешён — он не тянет ни UI, ни платформу.
- **Ф1.** В `fc_test_kit` заведён только `testPanel(...)`: сборка приложения в тестах
  осталась явной. Полноценный `testApp(...)` появится в Ф6 вместе с `initModules` и
  `AppOverrides` — раньше он был бы обёрткой над тем, что вот-вот изменится.
- **Ф2.** `typedef CommandFactory = AppCommand Function()` переименован в
  `AppCommandFactory`: имя `CommandFactory` занял фреймворк (`Command Function(CommandData)`).
  Ф6 всё равно предполагала это переименование.
- **Ф2.** Из референса добавлен `CommandFailure.rootCause`: составные команды вкладываются
  друг в друга, и падение шага приходит наверх завёрнутым несколько раз. Цепочка нужна
  журналу, разбирающему ошибку — причина.
- **Ф2.** У реестра появился `CommandErrorHandler`: ошибка команды **без окна** раньше
  пропадала бесследно (`run()` звал `execute()` без `await` и без `catch`). Теперь она
  доходит до обработчика, а приложение отдаёт туда журнал. Общее место для таких сообщений
  появится в Ф9 вместе с фоновыми работами.
- **Ф2.** Команда с окном **внутри** составной команды пока не поддержана: окно соберёт
  параметры само, а группа в это время будет ждать её завершения. Ограничение описано в
  `CommandRegistry.beforeExecution` и снимается в Ф9.
- **Ф2.** Побочно исправлено: команда, отказавшаяся устанавливаться (`init()` вернул
  `false`), больше не запускается через `create()`/`run()` — раньше перебор фабрик находил
  её несмотря на отсутствие прототипа.
- **Ф3.** Командный слой уехал в `fc_api` вместе с моделью, а не в Ф4: `Application.commands`
  тянет `CommandService`, тот — `AppCommand` и `KeyCombination`, и разрезать это по фазам
  нельзя. В Ф4 остаётся то, ради чего она и была: UI-kit, тема и разрыв импортов `view/*`
  из конкретных команд.
- **Ф3.** Ядро разложено по будущим модулям сразу: `lib/modules/local_fs/` (провайдер,
  обход каталога, отображение `dart:io`, временные файлы, окно, открытие системой),
  `lib/modules/zip/`, `lib/settings/`. Каталога `lib/model/` больше нет — Ф6 и Ф11 сведутся
  к `git mv` без правки кода.
- **Ф3.** `FileType.fromEntityType` и `FileAttributes.fromStat` заменены в API на
  `FileAttributes.fromMode(mode, permissions, type)`; разбор `FileSystemEntityType` и
  `FileStat` живёт в `lib/modules/local_fs/local_mapping.dart`.
- **Ф3.** `LocalCopySession` осталась в API целиком: платформенное в ней — только место под
  временные файлы, и оно вынесено в `StagingArea`/`StagedDirectory`. Реализация —
  `LocalStagingArea` в модуле локальной ФС; `ZipTreeProvider.open` получает её параметром.
- **Ф3.** `FileTableHeaderCell.titleOf` больше не хранит названия колонок: они стали
  `extension FsColumnTitle on FsColumn` в API — это и закрывает зависимость справки от
  виджета таблицы (блокер Ф4).
- **Ф3.** Тесты командного фреймворка переехали в `dependency/api/test/`: они не нуждаются
  ни в приложении, ни в подставках, и пакет проверяется отдельной командой. Тесты модели
  пока живут в приложении — они опираются на `fc_test_kit`, который зависит от ядра.
- **Ф4.** Тема разрезана: `FcTheme`, `FcColors`, `FcMetrics`, `FcIcons` — в `fc_api`,
  а сборка `ThemeData` (`AppTheme.theme`) осталась в ядре. В Ф5 она и уйдёт — вместе
  с `ThemeService`.
- **Ф4.** `help_table.dart` стал `src/ui/key_value_table.dart`, а его классы —
  `FcKeyValueTable`, `FcTableSection`, `FcTableRow`: это обычная таблица «ключ → значение»,
  и справка — лишь один из её случаев (дальше настройки, свойства объекта).
- **Ф4.** Ловушка ширины `FcButton` починена в самом виджете: `Align(widthFactor: 1)`
  снаружи и `Center(widthFactor: 1)` вместо `alignment` у `Container` внутри. Прежний
  `alignment` заставлял кнопку занимать всю предложенную ширину. `CommandDialogActions`
  остался — он про раскладку ряда (линия, правый край, ужимание), а не про починку ширины.
  Голдены после правки совпали пиксель-в-пиксель.
- **Ф4.** В набор добавлены `FcLabel`, `FcText`, `FcCheckbox`, `FcRadioGroup` и публичный
  `FcErrorText` (был приватным). Флажок и переключатель облегают содержимое так же, как
  кнопка, — иначе щелчок ловился бы по всей ширине окна.
- **Ф4.** Инверсия слоёв закрыта полностью: ни один файл в `lib/state/commands/` больше не
  импортирует `lib/view/**`.
- **Ф5.** Оформление стало сменным целиком: `FcIcons` и новый `FcFonts` — инстансные,
  `FcMetrics.scale`/`fontScale` — поля конструктора (одно число меняет размер всего
  интерфейса), `FcTheme` собирает всё вместе. `AppTheme.theme` заменён функцией
  `buildThemeData(FcThemeSpec)`.
- **Ф5.** `ThemeService` живёт в API, реализация `ThemeController` — в ядре и доступна как
  `Application.theme`. Пока ни одна тема не установлена, приложение работает на
  `FcThemeSpec.fallback` — модуль темы можно отключить, и это не повод не запускаться.
- **Ф5.** `IconData` собирается из кода глифа и шрифта темы, поэтому константой быть не
  может; на `non_const_argument_for_const_parameter` в одном месте стоит `ignore`
  с пояснением — это осознанный отказ от константности, а не недосмотр.
- **Ф5.** Голдены совпали пиксель-в-пиксель: значения по умолчанию не менялись, и это
  и было проверкой переноса.
- **Ф6.** `FcRegistrar` получил `services` — ленивую ссылку на службы приложения. Иначе
  модулю негде взять зависимость для фабрики: во время `install` контейнера ещё нет, а
  подписывать каждую фабрику типом `FcServices Function` значило бы утроить сигнатуры.
- **Ф6.** Фабрика команды модуля (`FcCommandFactory`) принимает `FcContext`, а реестр
  по-прежнему держит `AppCommandFactory` без аргументов: окружение подставляется при сборке.
  Так реестр не знает про модульную систему, а модуль — про реестр.
- **Ф6.** Сборка выявила две дыры в портированном фреймворке, обе чинились по образцу
  референса: (1) составная команда не отдавала свои данные наружу, и шаг, созданный через
  `create`, терял результат предыдущего — теперь данные исполнителя **и есть** его
  результат (`CommandExecutor implements ResultCommand<CommandData>`); (2) из-за этого
  цепочка данных замкнулась сама на себя и поиск уходил в бесконечность — добавлен тот же
  флаг обхода, что и в Spicelib (`inProgress`). Обе дыры закрыты тестами.
- **Ф6.** `AppContext` удалён; на его месте `lib/bootstrap/` — `Registrations`,
  `AppContainer`, `AppRuntime`, `AppBootstrapCommand` + `initModules`. Подмена служб в
  тестах теперь через `AppOverrides`, а не через параметры конструктора контейнера.
- **Ф6.** Команды пока держатся вместе модулем `LegacyCommands`: разъезжаться они начнут
  в Ф7 и Ф10, а `defaultCommandRegistry()` останется до Ф13 — её используют два десятка
  тестов, и переписывать их дважды незачем.
- **Ф6.** Замечена шероховатость API: у `AppCommand` уже есть `context` (условия запуска),
  поэтому окружение модуля команде приходится держать под другим именем. Решать это будем
  на настоящем модуле в Ф7 — либо переименованием, либо тем, что окружение вообще не
  придётся хранить.
- **Ф6.** Проверено сборкой настоящего приложения: `flutter build macos --debug` проходит.
- **Ф7.** `testApp(...)` в `fc_test_kit` появился раньше, чем предполагалось (Ф6 откладывала
  его): без него тест модуля вынужден собирать приложение вручную и знать про его внутренности.
  Заодно в наборе появились `InMemorySettingsStore` и `TestPlatform`.
- **Ф7.** Настройки в тестах теперь в памяти. Виджет-тесты идут в поддельном времени, и
  настоящее чтение с диска в них **не завершается никогда** — приложение, собранное через
  `initModules` с обычным хранилищем, просто повисало на шаге чтения настроек.
- **Ф7.** `AppOverrides` получил `saveDelay`: отложенная запись настроек с задержкой в
  секунду оставалась висеть таймером и роняла виджет-тесты. Раньше каждый тест задавал
  задержку сам, теперь это делает `testApp`.
- **Ф7.** `lib/bootstrap/app_modules.dart` — единственный список модулей: `appModules()` для
  запуска и `featureModules()` для тестов (без платформенных, их подменяет `testApp`).
  `main.dart` от этого не перестал быть местом, где список задан, — он просто перестал быть
  единственным его читателем.
- **Ф7.** Тесты, проверявшие «набор команд по умолчанию» (Esc, пробел против перехода к
  имени, `Cmd-H` на macOS, запуск любой команды без клавиатуры), переехали в
  `dependency/navigation/test/navigation_bindings_test.dart`: набор собирается из модулей,
  и следить за ним нужно там, где он объявлен.
- **Ф7.** `OpenNodeCommand`/`OpenWithSystemCommand` больше не подставляют себе
  `openWithSystem`: платформенной реализации у модуля нет, служба приходит снаружи.
- **Ф7.** Голдены снова совпали: порядок команд в справке от переезда не изменился.
- **Ф8.** `FcRegistrar.settings` отдаёт раздел сразу, а содержимое у него появляется позже:
  модуль объявляет себя раньше, чем настройки прочитаны с диска. Обращение из `install`
  даёт внятную ошибку, обычное место для чтения — стартовая команда.
- **Ф8.** Вскрылась давняя потеря настроек: `AppController.settings` собирал снимок заново
  и **терял `sizeScanConcurrency`** — пользовательское значение переписывалось умолчанием
  при первой же записи. Теперь и оно, и разделы модулей переносятся из прочитанного;
  на это есть тесты.
- **Ф8.** Разделы модулей — живые объекты: снимок настроек несёт тот же `ModuleSettings`,
  а не копию. Иначе изменение раздела не попадало бы в отложенную запись.
- **Ф8.** Конверторы сериализации терпимы: число в поле строки станет строкой. «Мусором»
  считается только раздел, который вовсе не объект, — такой пропускается целиком.
- **Ф9.** Фоновые работы держит реестр команд: «фон» — это ровно «запуск без окна», а про
  запуски и их окна реестр знает и так. `Application.background` отдаёт его же как
  `BackgroundTasks`.
- **Ф9.** Отмена из фона не молчаливая: операция переспрашивает, и вопрос **возвращает окно
  на вид** — отвечать за пользователя ядро не вправе. Прежнее правило «нет окна → ответ по
  умолчанию» теперь звучит как «нет окна **и** не в фоне».
- **Ф9.** Кнопка «Background» появляется в окне хода работы, только пока работа идёт:
  у не начавшейся прятать нечего.
- **Ф9.** `PanelViewports` уехал в `src/ui/`: он возвращает виджет, а доктринальный тест
  чистоты честно поймал его в «чистом» каталоге. Это ровно тот случай, ради которого тест
  и заводился.
- **Ф9.** `AppController.viewports` необязателен: приложению без экрана (тест состояния,
  сценарий) рисовать нечем и незачем — тогда подставляется `NoPanelViewports`.
- **Ф9.** Виджет-тесты, собиравшие `AppController` вручную, переведены на `testApp`:
  без реестра видов содержимого панель рисовала пустоту. Голдены после этого совпали —
  и это заодно проверка того, что новая развязка ничего не изменила.
- **Ф10.** `AppOverrides` получил `rightProvider`: тесту переноса нужны панели на разных
  источниках. В настоящем приложении панели расходятся, войдя в архив, — тесту этот путь
  ни к чему, а проверяет он именно перенос между провайдерами.
- **Ф10.** Заглушки `file.view`/`file.edit` (F3/F4) остались в ядре вместе со справкой:
  это ещё не модули, а обещание, что клавиша занята. Уедут вместе с просмотрщиком
  и редактором.
- **Ф10.** Тесты файловых операций собирают приложение из двух модулей — своего и
  навигации: ходить по дереву им всё равно нужно, а зависеть от полного списка модулей
  приложения — нет.
- **Ф11.** `archive` ушёл из зависимостей приложения в зависимости модуля: формат архива —
  дело того, кто его читает.
- **Ф11.** Тесты архива зависят от приложения: zip требует произвольного доступа к файлу,
  поэтому они работают с настоящим диском — локальный провайдер и место под временные
  файлы берутся оттуда. Это честная зависимость теста, а не модуля: сам `fc_zip_archiver`
  знает только API.
- **Ф12.** Голден справки перегенерирован — **первый и единственный раз за весь
  рефакторинг**. Причина содержательная, а не оформительская: в списке команд появилась
  новая (`app.theme.use`), а порядок команд теперь задаётся порядком модулей. Остальные
  два голдена не менялись ни разу.
- **Ф12.** `SwitchThemeCommand` и `RestoreThemeCommand` живут в модуле темы: без единой
  темы переключать нечего, и команда там же, где и то, чем она распоряжается. Второй теме
  (светлой) достаточно будет объявить свой `FcThemeSpec` — команды у неё уже есть.
- **Ф12.** Клавиши у смены темы нет намеренно: её место — в списке команд, который
  появится отдельным модулем. Команда без привязки работает — это проверялось ещё в Ф2.

## Проверка

- После **каждой** фазы: `flutter analyze` (чисто) и `flutter test` (зелёный) из корня —
  воркспейс прогоняет и пакеты.
- Перед Ф4: зафиксировать зелёный базис голденов `flutter test test/view`; после Ф4 и Ф5 —
  сравнить `test/view/goldens/{application_view,copy_dialog,help_dialog}.png`; расхождение
  считать багом переноса, а не поводом для `--update-goldens` (регенерация — только после
  визуальной сверки с `docs/design/design.png`).
- Отдельный полный прогон сразу после Ф2: там перестают глотаться исключения из `run()`.
- Ручной прогон приложения (`flutter run -d macos`) после Ф6, Ф9 и Ф12: вход в zip-архив,
  копирование с прогрессом и Esc посреди работы, уход операции в фон и возврат, F1-справка,
  переключение темы.
- Приёмочный критерий всего рефакторинга: `fc_default_theme` и `fc_zip_archiver` не
  импортируют ничего, кроме `package:fc_api/fc_api.dart` (+ `archive` у zip), а
  `lib/main.dart` — единственное место в ядре, знающее имена модулей.
