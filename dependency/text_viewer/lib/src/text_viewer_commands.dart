import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

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
  String get label => _viewerOf(_app)?.wordWrap == true ? tr('Unwrap') : tr('Wrap');

  /// Название меняется по состоянию, а ищут всегда одним словом.
  @override
  Set<String> get keywords => const {'word wrap', 'line wrap'};

  @override
  String get description => tr('Wrap long lines in the viewer');

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
    context.app.toasts.show(screen.wordWrap ? tr('Wrap: On') : tr('Wrap: Off'));
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
  String get label => tr('Line Num');

  @override
  Set<String> get keywords => const {'line numbers', 'gutter'};

  @override
  String get description => tr('Show line numbers in the viewer');

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
    context.app.toasts.show(screen.showLineNumbers ? tr('Show line numbers: On') : tr('Show line numbers: Off'));
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
  String get label => tr('Copy');

  @override
  String get description => tr('Copy the selected text to the clipboard');

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
    context.app.toasts.show(plural(text.length, one: 'Copied {n} character', other: 'Copied {n} characters'));
  }
}

/// Отформатированная копия или исходник.
///
/// Форматирует не сама: умение приносит модуль форматтера, а команда берёт из
/// реестра первого, кто взялся за этот файл (`docs/spec/formatters.md`, §3).
/// Реестр пуст — брать нечего, и команда невыполнима: ряд кнопок показывает
/// подпись приглушённой.
class ToggleFormatCommand extends AppCommand {
  ToggleFormatCommand({required this.maxSize});

  static const String commandId = 'text.format';

  /// Предел размера — настройкой модуля. Спрашивается при каждом нажатии:
  /// настройку могли только что поменять.
  final int Function() maxSize;

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
  /// Оговорка у «Format» нужна: без неё это слово значит формат файла («Формат»
  /// у архивов и картинок), а здесь — «разложить по строкам».
  @override
  String get label => textViewerInFocus(_app)?.formatted == true ? tr('Raw') : tr('Format', context: 'text');

  /// «format» здесь лишнее: оно и есть подпись. А вот «json», «pretty» и
  /// «raw» — то, чем этот переключатель ищут, не зная его имени.
  @override
  Set<String> get keywords => const {'pretty', 'indent', 'json', 'raw', 'source'};

  @override
  String get description => tr('Show the text formatted');

  /// Форматтер для показанного файла — первый по приоритету, кто взялся.
  ///
  /// Тип содержимого показу неизвестен: файл уже прочитан, и определять его
  /// ради ответа «моё ли» никто не станет (`docs/spec/formatters.md`, §2).
  static FormatterSpec? _formatterFor(Application app, TextViewerScreen screen) {
    for (final spec in app.formatters) {
      if (spec.accepts(screen.entry, null)) {
        return spec;
      }
    }

    return null;
  }

  /// Назад к исходнику можно всегда: он на руках. Вперёд — только если за файл
  /// кто-то берётся.
  ///
  /// Предел размера здесь **не** спрашивается нарочно: приглушённая подпись не
  /// объясняет, почему, а нажатие обязано ответить. Отказ приходит тостом.
  @override
  bool isExecutable(CommandContext context) {
    final screen = textViewerInFocus(context.app);
    if (screen == null) {
      return false;
    }

    return screen.formatted || _formatterFor(context.app, screen) != null;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final screen = textViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    if (screen.formatted) {
      screen.showRaw();

      return;
    }

    final spec = _formatterFor(context.app, screen);
    if (spec == null) {
      return;
    }

    final limit = maxSize();
    if (screen.entry.size > limit) {
      // На файле в сто мегабайт красота не стоит замершего окна
      // (`docs/spec/formatters.md`, §9).
      context.app.toasts.show(
        tr(
          'Too large to format: {size}, limit is {limit}',
          args: {'size': formatBytesLong(screen.entry.size), 'limit': formatBytesLong(limit)},
        ),
      );

      return;
    }

    try {
      screen.showFormatted(spec.format);
    } on FormatException catch (error) {
      // Отказ действия — тостом; на экране остаётся исходник: пустой экран не
      // объясняет ничего (`docs/spec/formatters.md`, §6).
      context.app.toasts.show(_refusal(spec.title, error, screen.raw));
    }
  }

  /// Отказ называет место: «строка 4, столбец 12» ведёт прямо туда, а смещение
  /// в знаках человеку не говорит ничего.
  String _refusal(String what, FormatException error, String text) {
    final place = placeOfError(error, text);
    final why = error.message;
    if (place == null) {
      return tr('Not valid {what}: {why}', args: {'what': what, 'why': why});
    }

    return tr(
      'Not valid {what}: {why} at line {line}, column {column}',
      args: {'what': what, 'why': why, 'line': place.line, 'column': place.column},
    );
  }
}
