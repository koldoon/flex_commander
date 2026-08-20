import 'package:fc_api/fc_api.dart';

import 'syntax/re_highlighter.dart';
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
  Future<void> execute() async {
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

    context.app.screens.open(
      ViewerScreen(
        node: node,
        document: document,
        highlighterFor: ReHighlighter.new,
        wordWrap: settings.wordWrap,
        onWrapChanged: (value) {
          settings.wordWrap = value;
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

  @override
  String get description => 'Wrap long lines in the viewer';

  static ViewerScreen? _viewerOf(Application? app) {
    final screen = app?.screens.active;
    return screen is ViewerScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _viewerOf(context.app) != null;

  @override
  Future<void> execute() async => _viewerOf(context.app)?.toggleWordWrap();
}

/// Подвинуть показ.
///
/// Одна команда на все восемь клавиш: куда двигать, приходит значением
/// привязки — тот же приём, что у панелей с их курсором.
class ScrollViewerCommand extends AppCommand {
  static const String commandId = 'viewer.scroll';

  /// Имя значения в привязке.
  static const String stepParam = 'step';

  @override
  String get id => commandId;

  @override
  String get label => 'Scroll';

  @override
  String get description => 'Move the viewer';

  @override
  bool isExecutable(CommandContext context) => context.app.screens.active is ViewerScreen;

  @override
  Future<void> execute() async {
    final screen = context.app.screens.active;
    final name = param<String>(stepParam);
    if (screen is! ViewerScreen || name == null) {
      return;
    }

    final step = ScrollStep.values.where((value) => value.name == name).firstOrNull;
    if (step != null) {
      screen.scroll(step);
    }
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
  String get description => 'Close the viewer';

  @override
  bool isExecutable(CommandContext context) => context.app.screens.active?.id == ViewerScreen.screenId;

  @override
  Future<void> execute() async => context.app.screens.close(ViewerScreen.screenId);
}
