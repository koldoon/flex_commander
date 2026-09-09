import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_info_screen.dart';
import 'file_info_view.dart';

/// Сведения об объекте — окном.
///
/// `Cmd-I` с макоси и `Alt-Enter` из коммандеров: обе привычки настоящие, и
/// спорить им не с чем.
class FileInfoCommand extends AppCommand {
  static const String commandId = 'file.info';

  @override
  String get id => commandId;

  @override
  String get label => tr('Info');

  @override
  Set<String> get keywords => const {'properties', 'details', 'about', 'attributes'};

  @override
  String get description => tr('Everything known about the object under the cursor');

  @override
  bool isExecutable(CommandContext context) => context.session.hasTargets;

  /// Помеченное, а нет пометки — то, что под курсором. Псевдоузел «..» не в
  /// счёт: сведения о нём — это сведения о каталоге, куда он ведёт, и
  /// показывать их под его именем значило бы путать.
  /// Помеченное, а нет пометки — то, что под курсором.
  List<FileEntry> _targetsOf(CommandContext context) => [
    for (final entry in context.targets)
      if (!entry.isParent) entry,
  ];

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final targets = _targetsOf(context);
    if (!panel.hasTargets) {
      return;
    }

    final view = context.app.view;
    // Окно встаёт с тем, что видно, и дополняется целиком, когда ядро ответит:
    // помеченного в других каталогах у этой стороны значением нет вовсе
    // (`docs/spec/operation-targets.md`, §2).
    final screen = FileInfoScreen(app: context.app, entries: targets, contentOf: panel.contentOf);
    late final String dialogId;
    void close() {
      view.closeDialog(dialogId);
      screen.close();
    }

    dialogId = view.showDialog(
      DialogSpec(
        // Счёт — по путям: они приезжают полными, и ждать ради числа нечего.
        title: _titleOf(context),
        takesFocus: true,
        // Разделы те же, что в панели: разметка одна, рама разная.
        content: ListenableBuilder(
          listenable: screen,
          builder:
              (context, _) => FcKeyValueTable(
                sections: sectionsOf(screen, context.strings),
                onClose: close,
                // Размер каталога — кнопкой, рядом с «Close»: обход дерева при
                // открытии окна недопустим.
                actions: [
                  if (screen.canCount && screen.directorySize == null)
                    FcButton(
                      label: screen.counting ? tr('Counting…') : tr('Calculate'),
                      onPressed: screen.counting ? null : screen.count,
                    ),
                ],
              ),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );

    // Окно уже стоит — теперь можно и спросить, что помечено на самом деле.
    unawaited(panel.allTargets().then(screen.adopt));
  }

  /// Заголовок: одна вещь — её имя, несколько — их число.
  ///
  /// Считается по путям целей: помеченное бывает из разных каталогов, а строк
  /// своего списка на всех не хватит (`docs/spec/operation-targets.md`, §2).
  String _titleOf(CommandContext context) {
    final paths = context.session.targetPaths;
    if (paths.length == 1) {
      final path = paths.single;
      final seen = context.session.entries.where((entry) => entry.path == path).firstOrNull;
      return seen?.name ?? _nameOf(path);
    }
    return plural(paths.length, one: '{n} item', other: '{n} items');
  }

  static String _nameOf(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }
}
