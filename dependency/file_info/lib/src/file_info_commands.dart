import 'package:fc_core_api/fc_core_api.dart';
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
  String get label => 'Info';

  @override
  Set<String> get keywords => const {'properties', 'details', 'about', 'attributes'};

  @override
  String get description => 'Everything known about the object under the cursor';

  @override
  bool isExecutable(CommandContext context) => _targetsOf(context).isNotEmpty;

  /// Помеченное, а нет пометки — то, что под курсором. Псевдоузел «..» не в
  /// счёт: сведения о нём — это сведения о каталоге, куда он ведёт, и
  /// показывать их под его именем значило бы путать.
  List<FsNode> _targetsOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute(CommandContext context) async {
    final targets = _targetsOf(context);
    if (targets.isEmpty) {
      return;
    }

    final view = context.app.view;
    final screen = FileInfoScreen(app: context.app, nodes: targets);
    late final String dialogId;
    void close() {
      view.closeDialog(dialogId);
      screen.close();
    }

    dialogId = view.showDialog(
      DialogSpec(
        title: targets.length == 1 ? targets.single.name : '${targets.length} items',
        takesFocus: true,
        // Разделы те же, что в панели: разметка одна, рама разная.
        content: ListenableBuilder(
          listenable: screen,
          builder:
              (context, _) => FcKeyValueTable(
                sections: sectionsOf(screen),
                onClose: close,
                // Размер каталога — кнопкой, рядом с «Close»: обход дерева при
                // открытии окна недопустим.
                actions: [
                  if (screen.canCount && screen.directorySize == null)
                    FcButton(
                      label: screen.counting ? 'Counting…' : 'Calculate',
                      onPressed: screen.counting ? null : screen.count,
                    ),
                ],
              ),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }
}
