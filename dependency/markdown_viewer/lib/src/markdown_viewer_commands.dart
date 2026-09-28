import 'package:fc_ui_api/fc_ui_api.dart';

import 'markdown_viewer_screen.dart';

/// Показ markdown, которому сейчас принадлежит ввод.
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — этот документ. Клавиша принадлежит тому, что видно.
MarkdownViewerScreen? markdownViewerInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);

  return content is MarkdownViewerScreen ? content : null;
}

/// Свёрстанный документ или его исходник.
class ToggleMarkdownFormatCommand extends AppCommand {
  static const String commandId = 'markdown.format';

  /// Приложение для **прототипа**: подпись спрашивают и тогда, когда никакого
  /// запуска нет, — ряд кнопок читает её прямо у него.
  Application? _app;

  @override
  bool init(Application app) {
    _app = app;

    return true;
  }

  @override
  String get id => commandId;

  /// Подпись говорит, что клавиша сделает **сейчас**, — как и везде в ряду.
  /// Оговорка у «Format» нужна: без неё это слово уже значит формат файла
  /// («Формат» у архивов и картинок), а здесь — «свёрстано».
  @override
  String get label => markdownViewerInFocus(_app)?.formatted == true ? tr('Raw') : tr('Format', context: 'markdown');

  @override
  Set<String> get keywords => const {'markdown', 'source', 'rendered', 'preview'};

  @override
  String get description => tr('Show the document formatted or as it is written');

  @override
  bool isExecutable(CommandContext context) => markdownViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    markdownViewerInFocus(context.app)?.toggleFormat();
  }
}
