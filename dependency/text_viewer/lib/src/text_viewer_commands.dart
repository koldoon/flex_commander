import 'package:fc_api/fc_api.dart';

import 'text_viewer_screen.dart';

/// Показ текста, которому сейчас принадлежит ввод.
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — текст. Клавиша принадлежит тому, что видно.
TextViewerScreen? textViewerInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);
  return content is TextViewerScreen ? content : null;
}

/// Переключить перенос строк.
class ToggleWordWrapCommand extends AppCommand {
  static const String commandId = 'text.wrap';

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

  static TextViewerScreen? _viewerOf(Application? app) => textViewerInFocus(app);

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
class ToggleLineNumbersCommand extends AppCommand {
  static const String commandId = 'text.numbers';

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

  static TextViewerScreen? _viewerOf(Application? app) => textViewerInFocus(app);

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

  static const String commandId = 'text.copy';

  final ClipboardService clipboard;

  @override
  String get id => commandId;

  @override
  String get label => 'Copy';

  @override
  String get description => 'Copy the selected text to the clipboard';

  static TextViewerScreen? _viewerOf(Application app) => textViewerInFocus(app);

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
