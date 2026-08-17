# Flex Commander — спецификация разработки

Классический двухпанельный файловый менеджер (в традиции Norton/Total/Far Commander)
на Flutter Desktop. Основной способ работы — клавиатура.

Спецификация опирается на два источника:

- **Внешний вид** — [`design/design.svg`](design/design.svg) (`design.png` — растровая копия);
- **Архитектура** — референсная реализация на Adobe Flex/AIR:
  `~/Developer/Flex Projects/flex-commander` (пакет `ru.koldoon.fc`).
  Там уже отработаны слой моделей (дерево узлов с подключаемыми провайдерами),
  модель команд с привязками клавиш и асинхронные операции с прогрессом.
  Ниже по тексту она называется «референс».

## Документы

| Файл | Содержание |
|------|-----------|
| [`models.md`](models.md) | Слой моделей: дерево узлов, провайдеры, асинхронные операции, колонки, сортировка, настройки |
| [`state.md`](state.md) | Управление состоянием: контроллеры панелей, команды, поток данных, сохранение настроек |
| [`widgets.md`](widgets.md) | Дерево виджетов, описание каждого виджета, тема и метрики из макета |
| [`keyboard.md`](keyboard.md) | Клавиатура, фокус, реестр команд, нижняя панель F-кнопок |
| [`providers.md`](providers.md) | Архивы и сетевые ФС: разбор нынешних контрактов, сравнение с TC/Far/MC, что менять |

## Объём первого этапа (MVP)

Входит:

- Два независимых файловых списка, между которыми переключается фокус.
- Отображение каталога: тип объекта (каталог / файл / ссылка), имя, расширение, размер,
  дата, атрибуты.
- Таблица с настраиваемым набором колонок: состав, порядок, ширина, видимость.
- Сортировка кликом по заголовку колонки; повторный клик меняет направление.
- Навигация с клавиатуры: `↑`/`↓`/`PgUp`/`PgDn`/`Home`/`End` — курсор,
  `Tab` — смена активной панели, `Enter` — вход в каталог, `Backspace` — на уровень вверх.
- Пометка объектов (`Space`, `Insert`), строка состояния панели.
- Нижняя панель функциональных кнопок F1…F10, синхронизированная с реестром команд.
- Сохранение между запусками: пути панелей, раскладка колонок, сортировка, геометрия окна.
- Оформление референсного приложения: палитра, шрифты, формы кнопок и окон, отступы
  (см. [`widgets.md`](widgets.md)). Тема одна — светлого варианта нет.
- Файловые операции: создание каталога, удаление, копирование и перенос.

Не входит в MVP (закладывается архитектурно, реализуется позже):

- Вложенные провайдеры дерева (архивы, sftp) — интерфейсы закладываются, реализация одна: локальная ФС.
- Встроенные просмотрщик и редактор (F3/F4), вкладки, история, закладки, поиск, drag&drop.

## Архитектура

Слои, снизу вверх. Зависимости направлены строго вверх: `view` знает про `state`,
`state` — про `model`, `model` не знает ни про что, кроме себя и `dart:io`.

```
┌──────────────────────────────────────────────┐
│ view/      виджеты, тема, форматирование     │  Flutter
├──────────────────────────────────────────────┤
│ state/     реализации Application и Panel,   │  чистый Dart + foundation
│            реестр команд, привязки клавиш    │
├──────────────────────────────────────────────┤
│ model/     API приложения (Application,      │  чистый Dart + dart:io
│            Panel, TreeProvider…), дерево     │
│            узлов, операции, настройки        │
└──────────────────────────────────────────────┘
```

Интерфейсы живут в нижнем слое, реализации — в верхнем: так команда (и любой
будущий модуль) зависит от API, а не от конкретных классов, и стрелки зависимостей
не разворачиваются.

Ключевая идея слоя моделей взята из референса и сохранена целиком:
**панель показывает не «список файлов», а каталог в дереве узлов**, а всё, что умеет
читать и изменять это дерево, спрятано за интерфейсом `TreeProvider`. Локальная ФС —
всего лишь одна из его реализаций; архив или удалённая ФС подключаются как ещё один
провайдер, а панель, курсор, пометка, сортировка и команды остаются неизменными.
Подробно — в [`models.md`](models.md).

Принципы:

1. **Слой интерфейсов — это API приложения.** `Application`, `Panel`,
   `PanelSelection`, `TreeProvider`, `AsyncOperation` описывают, что умеет
   приложение; контроллеры их реализуют. Команды пишутся только против
   интерфейсов, поэтому реализацию можно менять, не трогая ни одну команду.
   Так же устроен референс (`IApplication`, `IPanel`, `IPanelSelection`).
2. **Панель работает с `FsNode`, а не с путями.** Путь — производная величина
   (`node.pathString`), а не первичный ключ.
3. **Всё, что обращается к ФС, асинхронно и отменяемо.** Никаких синхронных `statSync`
   в дереве виджетов.
4. **Контроллеры не знают о виджетах.** Никаких `BuildContext` в `state/`.
5. **Действия — это команды**, а не обработчики в виджетах: команда описывает только
   себя — название, условие выполнимости и поведение. Она не знает **чем её вызвали**,
   **какими клавишами** и **где её показывают**: привязками заведует реестр, а кнопки
   внизу окна — это нарисованная клавиатура, которая сама спрашивает, что закреплено
   за `F5`. Опирается команда лишь на активную панель и выбранные объекты. Поэтому
   привязки станут настраиваемыми, а любую команду можно будет выполнить из списка
   команд. Разное поведение — это разные команды, а не параметры одной
   (см. [`keyboard.md`](keyboard.md#команда-не-знает-чем-её-вызвали)).
6. **Одна панель — один контроллер.** Панели симметричны и не знают друг о друге;
   их связывает `AppController` (активная / пассивная = источник / приёмник операции).
7. **Никаких внешних пакетов управления состоянием.** `ChangeNotifier` +
   `InheritedNotifier` покрывают задачу; дерево состояния маленькое и статичное.
8. **Службы создаёт контейнер зависимостей**, а не вызывающий код: весь граф
   собран в `AppContext` (`dicom`), зависимости создаются лениво и приходят
   параметрами конструкторов. Классы не тянут зависимости из глобальных точек:
   `inject<T>()` — только для точки сборки. Подробно — в
   [`state.md`](state.md#8-контейнер-зависимостей).

## Соответствие референсу

| Adobe Flex (`ru.koldoon.fc`) | Flutter |
|---|---|
| `m.tree.INode` / `AbstractNode` | `model/tree/fs_node.dart` → `FsNode` |
| `FileNode`, `DirectoryNode`, `LinkNode` | `FileNode`, `DirectoryNode`, `LinkNode` (те же роли) |
| `m.tree.ITreeProvider` | `TreeProvider` |
| `m.tree.ITreeEditor`, `IFilesProvider` | `TreeEditor`, `FilesProvider` (интерфейсы, реализация — после MVP) |
| `m.tree.impl.fs.LocalFileSystemTreeProvider` (через CLI `ls`/`stat`) | `LocalTreeProvider` (через `dart:io`) |
| `m.async.IAsyncOperation` + `IAsyncOperationStatus` | `AsyncOperation<T>` (`Future` + прогресс + отмена) |
| `m.interactive.IInteraction` | `OperationRequest` — запрос к пользователю из середины операции |
| `m.app.IApplication` | `Application` (интерфейс) + `AppController` (реализация) |
| `m.app.IPanel` | `Panel` + `PanelController` |
| `m.app.IPanelSelection` | `PanelSelection` + `SelectionController` |
| `m.app.ICommand` + `BindingProperties` | `AppCommand` + `KeyBinding` |
| `m.app.impl.ApplicationImpl.processKeyboardCombination()` | `CommandRegistry.dispatch()` |
| `conf.AppConfig` (`~/.flexnavigator/settings.json`) | `SettingsStore` (`~/.flex-commander/settings.json`) |
| `c.panel.impl.FilesPanel` | `PanelView` |
| `c.panel.impl.ColumnHeader` | `FileTableHeaderCell` |
| `c.panel.list.FileItemRenderer` | `FileTableRow` |
| `c.fn.FunctionKeyRenderer` | `FunctionButton` |

Что из референса сознательно **не** переносится:

- Работа с ФС через запуск внешних утилит (`ls`, `stat`, `cp`, `rsync`) — в AIR не было
  нормального API файловой системы, в Dart есть `dart:io`. Идея вернётся позже точечно:
  для копирования с прогрессом `rsync` по-прежнему удобнее.
- Собственная реализация промисов и сигналов (`org.osflash.signals`) — в Dart есть
  `Future`, `Stream` и `ChangeNotifier`.
- Хранение курсора и пометки внутри виджета списка (`FilesPanel` держал их в
  `spark.List`) — в Flutter это состояние контроллера, а список только рисует.

## Структура каталогов

```
lib/
  main.dart                        точка входа, настройка логирования, runApp
  app_context.dart                 контейнер зависимостей: весь граф приложения
  app.dart                         MaterialApp, тема, AppScope

  core/
    serialization.dart             Serializable и конверторы JSON: ниже всех слоёв,
                                   потому что им пользуются модели

  model/
    app/
      application.dart             Application — API приложения для команд
      panel.dart                   Panel, PanelStatus — API панели
      panel_selection.dart         PanelSelection — API пометки объектов
    tree/
      fs_node.dart                 FsNode, FileNode, DirectoryNode, LinkNode, ParentDirNode
      file_type.dart               FileType и его разбор
      file_attributes.dart         права доступа, флаги, executable
      tree_provider.dart           TreeProvider, TreeEditor, FilesProvider (интерфейсы)
      node_path.dart               разбор и сборка строк пути с учётом провайдеров
      local/
        local_tree_provider.dart   реализация поверх dart:io
        local_listing.dart         чтение каталога в изоляте
    async/
      async_operation.dart         AsyncOperation, OperationStatus, OperationProgress
      operation_request.dart       интерактивные запросы к пользователю
    panel/
      column_spec.dart             FsColumn, ColumnSpec, ColumnLayout
      sort_spec.dart               SortSpec, SortDirection, компараторы
    settings/
      app_settings.dart            AppSettings, PanelSettings
      window_geometry.dart         положение и размер окна
      settings_store.dart          чтение/запись settings.json
    os/
      system_open.dart             открытие объекта средствами системы
      window_service.dart          интерфейс управления окном
      plugin_window_service.dart   реализация поверх window_manager

  state/
    app_controller.dart            реализация Application
    panel_controller.dart          реализация Panel
    selection_controller.dart      реализация PanelSelection
    commands/
      app_command.dart             AppCommand, AsyncCommand, KeyBinding, CommandContext
      file_commands.dart           файловые операции: создание каталога, удаление
      key_combination.dart         нормализация нажатия в строку вида Ctrl-Shift-F5
      command_registry.dart        команды, привязки клавиш и разбор нажатий
      navigation_commands.dart     курсор, Tab, Enter, Backspace, Home/End
      selection_commands.dart      пометка объектов
      default_commands.dart        набор команд и привязок по умолчанию
    app_scope.dart                 InheritedNotifier-доступ к контроллерам

  view/
    application_view.dart          корневой макет окна
    keyboard_handler.dart          приём клавиатуры для всего окна
    panel/
      panel_view.dart              панель целиком
      panel_path_header.dart       «плашка» с текущим путём
      panel_status_bar.dart        строка состояния под списком
      file_table.dart              таблица: заголовки + прокручиваемые строки + вертикальные линейки
      file_table_header.dart       заголовки колонок: сортировка, ширина, порядок, видимость
      file_table_row.dart          одна строка файла
      file_type_icon.dart          иконка типа объекта
    function_bar/
      function_bar.dart            ряд F-кнопок внизу окна
      function_button.dart         одна кнопка
    common/
      split_view.dart              две панели с перетаскиваемым разделителем
    dialogs/
      command_dialog_layer.dart    рамка и заголовок окна команды
      command_dialog.dart          типовое содержимое: форма, вопрос, прогресс
    theme/
      app_theme.dart               ThemeData и расширение FcTheme
      app_colors.dart              палитра из макета
      app_metrics.dart             высоты, отступы, размеры шрифта
    format/
      size_format.dart             126 / 90.1K / 14.9M / 999.9G
      date_format.dart             19-02-2018
```

## Зависимости

Добавить в `pubspec.yaml`:

```yaml
dependencies:
  path: ^1.9.0            # basename/extension/join/normalize
  window_manager: ^0.5.1  # положение и размер окна между запусками
  dicom: ^0.0.3           # контейнер зависимостей
  logecom: ^0.0.11        # логирование
```

`path_provider` не понадобился: настройки лежат в домашнем каталоге
(`~/.flex-commander/settings.json`), как и в референсе.

Уже подключённые `go_router` и `dicom` для MVP не нужны — приложение одноэкранное;
их можно убрать из `pubspec.yaml`. `logecom` используется для логирования операций
и ошибок ФС (в референсе эту роль играл `SOSLoggingTarget`).

Платформа: сначала macOS (в проекте есть только `macos/`). Платформозависимые места
изолируются в `LocalTreeProvider` и `FileAttributes` (разбор режима доступа, корни дисков,
«корзина» при удалении).

**Песочница macOS выключена** (`macos/Runner/*.entitlements`). Файловому менеджеру нужен
доступ ко всей файловой системе, а в песочнице ему видна только папка-контейнер: туда же
подменяется и домашний каталог, так что настройки уезжают в
`~/Library/Containers/…/Data`, а попытка открыть, например, `~/Downloads` заканчивается
ошибкой ввода-вывода. Защита уровня системы (TCC) при этом остаётся: при первом заходе
в «Загрузки», «Документы» и на рабочий стол macOS один раз спросит разрешение —
пояснения для этих запросов лежат в `macos/Runner/Info.plist`.

## Этапы

| Этап | Результат |
|------|-----------|
| 1 | `FsNode`-дерево, `TreeProvider`, `LocalTreeProvider`, сортировка, форматтеры + unit-тесты (без UI) |
| 2 | `PanelController`, `PanelSelection`, `AppController`, `SettingsStore` + тесты на fake-провайдере |
| 3 | Вёрстка по макету: панели, таблица, заголовки, статусные строки, F-кнопки |
| 4 | Реестр команд и клавиатура: курсор, `Tab`, `Enter`, `Backspace`, пометка |
| 5 | Настройка колонок: ширина, порядок, видимость; сортировка кликом |
| 6 | Сохранение и восстановление состояния между запусками |
| 7 | `TreeEditor`: создание каталога, удаление, копирование и перенос — с прогрессом и вопросами по ходу работы |
| 8 | Оформление референсного приложения: палитра, шрифты, кнопки, окна команд, отступы |
