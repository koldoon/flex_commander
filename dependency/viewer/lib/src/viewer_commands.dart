import 'package:fc_api/fc_api.dart';

import 'text_document.dart';
import 'viewer_screen.dart';
import 'viewer_settings.dart';

/// Показать файл под курсором.
///
/// Идентификатор — тот же, что у заглушки оболочки (`file.view`): реестр
/// держит прототипы по идентификатору, и модуль, установленный позже, занимает
/// её место вместе с закреплённой за ней `F3`. В этом и смысл заглушек —
/// клавиша занята заранее, а команда приходит модулем.
class ViewFileCommand extends AppCommand {
  ViewFileCommand({required this.settings, required this.onSettingsChanged});

  /// Тот же идентификатор, что у заглушки `AppShell.viewCommand`.
  static const String commandId = 'file.view';

  final ViewerSettings settings;
  final void Function() onSettingsChanged;

  @override
  String get id => commandId;

  @override
  String get label => 'View';

  @override
  Set<String> get keywords => const {'viewer', 'preview', 'read', 'open file'};

  @override
  String get description => 'Show the file under the cursor as text';

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    // Каталог показывать нечем, псевдоузел «..» — тем более, а у источника
    // должно быть чем отдать содержимое: у результатов поиска, например,
    // байтов нет.
    return node != null && node is! DirectoryNode && node is! ParentDirNode && node.provider is FileContentProvider;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final node = context.node;
    if (node == null) {
      return;
    }

    final source = node.provider;
    if (source is! FileContentProvider) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    if (node.size > settings.maxFileSize) {
      // Отказ, а не начало файла: показывать кусок и называть его файлом —
      // значит врать о содержимом. Предел назван, и видно, где его менять.
      context.app.toasts.show(
        'File is too large: ${formatBytesLong(node.size)}, limit is ${formatSize(settings.maxFileSize)}',
      );
      return;
    }

    // Приведение, а не расчёт на вывод типа: `TreeProvider` и
    // `FileContentProvider` не связаны наследованием, и пересечение их
    // анализатор не выводит. Тем же приёмом пользуется движок переноса.
    final document = await TextDocument.read(node, source as FileContentProvider);

    context.app.view.pushViewportContent(
      ViewportPosition.fullscreen,
      ViewerScreen(
        node: node,
        text: document.text,
        wordWrap: settings.wordWrap,
        showLineNumbers: settings.showLineNumbers,
        onWrapChanged: (value) {
          settings.wordWrap = value;
          onSettingsChanged();
        },
        onLineNumbersChanged: (value) {
          settings.showLineNumbers = value;
          onSettingsChanged();
        },
      ),
    );
  }
}

/// Переключить перенос строк.
class ToggleWordWrapCommand extends AppCommand {
  static const String commandId = 'viewer.wrap';

  /// Приложение для **прототипа**: подпись у него спрашивают и тогда, когда
  /// никакого запуска нет, — ряд кнопок читает её прямо у него. Экземпляру
  /// запуска приложение приходит контекстом, и [init] у него не зовут.
  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  /// Подпись говорит, что клавиша сделает **сейчас**, — как и везде в ряду.
  @override
  String get label => _viewerOf(_app)?.wordWrap == true ? 'Unwrap' : 'Wrap';

  /// Название меняется по состоянию, а ищут всегда одним словом.
  @override
  Set<String> get keywords => const {'word wrap', 'line wrap'};

  @override
  String get description => 'Wrap long lines in the viewer';

  static ViewerScreen? _viewerOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);
    return screen is ViewerScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _viewerOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = _viewerOf(context.app);
    if (screen == null) {
      return;
    }

    screen.toggleWordWrap();
    // Переключилось и закончилось — о таком говорят всплывающим сообщением.
    // На узком файле подписи в ряду мало: она меняется, а текст на экране —
    // нет, и непонятно, сработала клавиша или нет.
    context.app.toasts.show('Wrap: ${screen.wordWrap ? 'On' : 'Off'}');
  }
}

/// Показать или спрятать номера строк.
class ToggleViewerNumbersCommand extends AppCommand {
  static const String commandId = 'viewer.numbers';

  @override
  String get id => commandId;

  /// Подпись постоянная — в отличие от переноса строк, где она меняется.
  ///
  /// Номера строк видно на самом экране, и скачущая подпись в ряду ничего к
  /// этому не добавляет, а мельтешит. О том, что переключилось, говорит
  /// всплывающее сообщение.
  @override
  String get label => 'Line Num';

  @override
  Set<String> get keywords => const {'line numbers', 'gutter'};

  @override
  String get description => 'Show line numbers in the viewer';

  static ViewerScreen? _viewerOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);
    return screen is ViewerScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _viewerOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = _viewerOf(context.app);
    if (screen == null) {
      return;
    }

    screen.toggleLineNumbers();
    context.app.toasts.show('Show line numbers: ${screen.showLineNumbers ? 'On' : 'Off'}');
  }
}

/// Скопировать выделенное в буфер обмена.
class CopySelectionCommand extends AppCommand {
  CopySelectionCommand(this.clipboard);

  static const String commandId = 'viewer.copy';

  final ClipboardService clipboard;

  @override
  String get id => commandId;

  @override
  String get label => 'Copy';

  @override
  String get description => 'Copy the selected text to the clipboard';

  static ViewerScreen? _viewerOf(Application app) {
    final screen = app.view.contentAt(ViewportPosition.fullscreen);
    return screen is ViewerScreen ? screen : null;
  }

  /// Копировать нечего, пока ничего не выделено: кнопка в ряду останется
  /// приглушённой, а не сделает вид, что сработала.
  @override
  bool isExecutable(CommandContext context) => _viewerOf(context.app)?.hasSelection ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    final text = _viewerOf(context.app)?.selection ?? '';
    if (text.isEmpty) {
      return;
    }

    await clipboard.writeText(text);
    // Случилось и закончилось — ровно то, о чём говорят всплывающим
    // сообщением.
    context.app.toasts.show('Copied ${text.length} characters');
  }
}

/// Закрыть просмотрщик и вернуться туда, откуда пришли.
class CloseViewerCommand extends AppCommand {
  static const String commandId = 'viewer.close';

  @override
  String get id => commandId;

  @override
  String get label => 'Quit';

  @override
  Set<String> get keywords => const {'close', 'exit', 'back'};

  @override
  String get description => 'Close the viewer';

  @override
  bool isExecutable(CommandContext context) => context.app.view.contentAt(ViewportPosition.fullscreen) is ViewerScreen;

  @override
  Future<void> execute(CommandContext context) async =>
      context.app.view.popViewportContent(ViewportPosition.fullscreen);
}
