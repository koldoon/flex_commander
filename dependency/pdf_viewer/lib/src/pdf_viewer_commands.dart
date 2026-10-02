import 'package:fc_ui_api/fc_ui_api.dart';

import 'pdf_viewer_screen.dart';

/// Показ PDF, которому сейчас принадлежит ввод.
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — этот показ.
PdfViewerScreen? pdfViewerInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);
  return content is PdfViewerScreen ? content : null;
}

/// По ширине окна или страница целиком.
class TogglePdfFitCommand extends AppCommand {
  static const String commandId = 'pdf.fit';

  /// Приложение для **прототипа**: подпись у него спрашивают и тогда, когда
  /// никакого запуска нет, — ряд кнопок читает её прямо у него.
  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  /// Подпись говорит, что клавиша сделает **сейчас**.
  @override
  String get label {
    final screen = pdfViewerInFocus(_app);
    if (screen != null && !screen.fits) {
      return screen.settings.wholePage ? tr('Whole page') : tr('Fit width');
    }
    return screen?.wholePage == true ? tr('Fit width') : tr('Whole page');
  }

  @override
  Set<String> get keywords => const {'zoom', 'fit'};

  @override
  String get description => tr('Fit pages to the window width or show the whole page');

  @override
  bool isExecutable(CommandContext context) {
    final screen = pdfViewerInFocus(context.app);
    return screen != null && !screen.showsText;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final screen = pdfViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    screen.toggleFit();
    // На документе, где страница и так во всю ширину, разницы может быть не
    // видно — сообщение говорит, что переключилось.
    context.app.toasts.show(screen.wholePage ? tr('Whole page') : tr('Fit width'));
  }
}

/// Страницы или текст документа (`docs/spec/pdf-viewer.md`, §8).
class TogglePdfTextCommand extends AppCommand {
  static const String commandId = 'pdf.text';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => pdfViewerInFocus(_app)?.showsText == true ? tr('Pages') : tr('Text', context: 'pdf');

  @override
  Set<String> get keywords => const {'copy', 'select', 'extract', 'pages'};

  @override
  String get description => tr('Show the text of the document instead of its pages');

  @override
  bool isExecutable(CommandContext context) => pdfViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = pdfViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    if (!await screen.loadText()) {
      // Нажатие не остаётся без ответа: у скана текста нет, и это говорится.
      context.app.toasts.show(tr('This PDF has no text — it is probably a scan'));
      return;
    }
    screen.toggleText();
  }
}

/// Приблизить или отдалить: множитель приходит значением.
class ZoomPdfCommand extends AppCommand {
  static const String commandId = 'pdf.zoom';

  /// Во сколько раз. Своё значение у каждой клавиши.
  static const String factorParam = 'factor';

  @override
  String get id => commandId;

  @override
  String get label => tr('Zoom');

  @override
  Set<String> get keywords => const {'scale', 'bigger', 'smaller'};

  @override
  String get description => tr('Zoom the pages in or out');

  @override
  bool isExecutable(CommandContext context) {
    final screen = pdfViewerInFocus(context.app);
    return screen != null && !screen.showsText;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final screen = pdfViewerInFocus(context.app);
    final factor = context.invocation.param<double>(factorParam);
    if (screen == null || factor == null) {
      return;
    }
    screen.zoomBy(factor);
  }
}
