import 'package:fc_api/fc_api.dart';

import 'image_viewer_screen.dart';

/// Показ картинки, которому сейчас принадлежит ввод.
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — этот показ. Клавиша принадлежит тому, что видно.
ImageViewerScreen? imageViewerInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);
  return content is ImageViewerScreen ? content : null;
}

/// Вписать в окно или показать точка в точку.
class ToggleImageFitCommand extends AppCommand {
  static const String commandId = 'image.fit';

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

  /// Подпись говорит, что клавиша сделает **сейчас**, — как и везде в ряду.
  @override
  String get label => imageViewerInFocus(_app)?.fitToWindow == true ? '1:1' : 'Fit';

  @override
  Set<String> get keywords => const {'zoom', 'actual size', 'fit to window'};

  @override
  String get description => 'Fit the image into the window or show it pixel for pixel';

  @override
  bool isExecutable(CommandContext context) => imageViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = imageViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    screen.toggleFit();
    // Переключилось и закончилось — о таком говорят всплывающим сообщением: на
    // картинке, которая и так помещалась, разницы не видно.
    context.app.toasts.show(screen.fitToWindow ? 'Fit to window' : 'Actual size');
  }
}

/// Приблизить или отдалить: множитель приходит значением.
class ZoomImageCommand extends AppCommand {
  static const String commandId = 'image.zoom';

  /// Во сколько раз. Своё значение у каждой клавиши: `+` и `-`.
  static const String factorParam = 'factor';

  @override
  String get id => commandId;

  @override
  String get label => 'Zoom';

  @override
  Set<String> get keywords => const {'scale', 'bigger', 'smaller'};

  @override
  String get description => 'Zoom the image in or out';

  @override
  bool isExecutable(CommandContext context) => imageViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = imageViewerInFocus(context.app);
    final factor = context.invocation.param<double>(factorParam);
    if (screen == null || factor == null) {
      return;
    }
    screen.zoomBy(factor);
  }
}

/// Следующая или предыдущая картинка того же каталога.
///
/// Листает **показ**, а не панель: курсор в ней остаётся там, откуда пришли, и
/// `Esc` возвращает ровно туда же.
class StepImageCommand extends AppCommand {
  StepImageCommand({required this.forward});

  static const String nextCommandId = 'image.next';
  static const String previousCommandId = 'image.previous';

  final bool forward;

  @override
  String get id => forward ? nextCommandId : previousCommandId;

  @override
  String get label => forward ? 'Next' : 'Previous';

  @override
  Set<String> get keywords => const {'image', 'album', 'browse'};

  @override
  String get description => forward ? 'Show the next image in the same directory' : 'Show the previous one';

  @override
  bool isExecutable(CommandContext context) {
    final screen = imageViewerInFocus(context.app);
    if (screen == null || screen.place != ViewerPlace.fullscreen) {
      // В панели стрелки не наши. Быстрый просмотр **следует за курсором** —
      // это его единственное обещание, и листать в обход курсора значило бы
      // показывать не то, на чём человек стоит.
      return false;
    }
    // В конце списка клавиша молчит: по кругу не ходим — конец есть конец.
    return forward ? screen.hasNext : screen.hasPrevious;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final screen = imageViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    try {
      await screen.step(forward ? 1 : -1);
    } on ViewerRefused catch (refusal) {
      // Соседняя картинка может не открыться — битая или слишком большая. Это
      // не повод закрывать показ: остаёмся на прежней и говорим причину.
      context.app.toasts.show(refusal.reason);
    }
  }
}
