import 'package:fc_api/fc_api.dart';

import 'quick_view_screen.dart';
import 'viewer_choice.dart';

/// Показать файл под курсором — во весь экран.
///
/// Чем показать, команда не решает: спрашивает реестр (`viewerFor`). Пока
/// просмотрщик был один, здесь стояло чтение текста; теперь читает тот, кто
/// взялся, — иначе команда неизбежно стала бы `switch` по видам файлов.
///
/// Идентификатор — тот же, что у заглушки оболочки (`file.view`): реестр
/// держит прототипы по идентификатору, и модуль, установленный позже, занимает
/// её место вместе с закреплённой за ней `F3`.
class ViewFileCommand extends AppCommand {
  /// Тот же идентификатор, что у заглушки `AppShell.viewCommand`.
  static const String commandId = 'file.view';

  @override
  String get id => commandId;

  @override
  String get label => 'View';

  @override
  Set<String> get keywords => const {'viewer', 'preview', 'read', 'open file'};

  @override
  String get description => 'Show the file under the cursor';

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    // Каталог показывать нечем, псевдоузел «..» — тем более. А вот «есть ли
    // кому взяться» здесь не спрашивается нарочно: команда работает, просто не
    // с этим файлом, и сказать об этом словами честнее, чем потухшей кнопкой.
    // Занятая панель второго чтения не начинает: она уже читает — либо каталог,
    // либо файл.
    return node != null && !context.panel.busy && node is! DirectoryNode && node is! ParentDirNode;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final node = context.node;
    if (node == null) {
      return;
    }

    try {
      // Открытие ведёт панель: файл может лежать на сервере, и до появления
      // экрана проходят секунды. Точка прерывания у просмотрщиков уже есть —
      // ею пользуется быстрый просмотр, — и отдаётся она прямо из работы.
      final content = await context.panel.runWork<ViewportState>((op) async {
        op.report(message: 'Reading ${node.name}…');
        return openViewer(context.app, node, ViewerPlace.fullscreen, checkpoint: op.checkpoint);
      });
      context.app.view.pushViewportContent(ViewportPosition.fullscreen, content);
    } on OperationCanceled {
      // Передумали — обычный ход дела: экран не открывается, говорить не о чем.
      return;
    } on ViewerRefused catch (refusal) {
      // Одно нажатие — одно сообщение: во весь экран отказ говорится тостом,
      // как и раньше. В быстром просмотре он же показывается словами в панели.
      context.app.toasts.show(refusal.reason);
    }
  }
}

/// Закрыть показ и вернуться туда, откуда пришли.
///
/// Закрывается **та область, в которой сейчас ввод**: показ бывает и во весь
/// экран, и наложением на панель, и `Esc` там значит одно и то же.
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
  bool isExecutable(CommandContext context) {
    final view = context.app.view;
    final shown = view.contentAt(view.activeArea);
    if (shown == null) {
      return false;
    }
    // Хозяин закрывается и тогда, когда показывать ему нечего: под курсором
    // каталог, и внутри у него слова, а не показ. Уйти оттуда всё равно надо.
    return shown is ViewportHost || innermost(shown) is ViewerContent;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    view.popViewportContent(view.activeArea);
  }
}

/// Быстрый просмотр в соседней панели.
///
/// `Shift-F3` — та же клавиша со слоем `Shift` рядом с обычным `F3`: то же
/// действие, только рядом, а не во весь экран.
///
/// Показ ложится **наложением** на область соседней панели. Под ним панель
/// цела — каталог, курсор, пометка, аренда, — а `panelAt` отдаёт для этой
/// области null, и `F5` туда становится невыполнимым сам собой.
class QuickViewCommand extends AppCommand {
  static const String commandId = 'viewer.quickView';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick View';

  @override
  String get description => 'Show what is under the cursor in the other panel';

  @override
  Set<String> get keywords => const {'preview', 'side by side', 'other panel', 'lister'};

  @override
  bool isExecutable(CommandContext context) => context.app.view.panelAt(context.app.view.sourceArea) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    final target = view.sourceArea.opposite;

    // Та же клавиша убирает то, что поставила.
    if (view.contentAt(target) is QuickViewHost) {
      view.popViewportContent(target);
      return;
    }

    final panel = view.panelAt(view.sourceArea);
    if (panel == null) {
      return;
    }

    view.pushViewportContent(target, QuickViewHost(app: context.app, panel: panel));
  }
}
