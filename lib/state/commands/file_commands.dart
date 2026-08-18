import 'package:flutter/material.dart';

import '../../model/tree/fs_node.dart';
import '../../model/tree/tree_provider.dart';
import '../../view/dialogs/command_dialog.dart';
import '../../view/theme/app_theme.dart';
import 'app_command.dart';
import 'async_command_base.dart';

/// Создание каталога в активной панели.
///
/// Работает и без интерфейса: задать имя параметром и вызвать [execute].
/// Окно — надстройка: оно задаёт тот же параметр и вызывает тот же [execute].
class MakeDirectoryCommand extends AppCommand {
  /// Имя нового каталога.
  static const String nameParam = 'name';

  final TextEditingController _name = TextEditingController();

  @override
  String get id => 'file.mkdir';

  @override
  String get label => 'Mk Dir';

  @override
  bool get hasDialog => true;

  /// Имя набирают сразу: фокус ставит поле ввода.
  @override
  bool get dialogTakesFocus => true;

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    // Провайдер может уметь только читать — тогда создавать нечем.
    return !panel.busy && panel.directory != null && panel.editor != null;
  }

  @override
  Future<void> execute() async {
    final panel = context.panel;
    final parent = panel.directory;
    final editor = panel.editor;
    final name = param<String>(nameParam)?.trim() ?? '';

    if (parent == null || editor == null) {
      return;
    }
    if (name.isEmpty) {
      throw const FsError('', FsErrorKind.invalidName);
    }

    final created = await editor.makeDirectory(parent, name).result;
    // Каталог создан на диске, но в панели его ещё нет: перечитываем и ставим
    // курсор на новый каталог, чтобы с ним можно было сразу работать.
    await panel.reload();
    panel.setCursorToName(created.name);
  }

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder:
          (context, _) => CommandDialogForm(
            error: error,
            onCancel: dismiss,
            onSubmit: submit,
            submitLabel: 'Create',
            // Поля те же, что в референсе: имя и каталог, в котором создаём.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommandDialogField(
                  label: 'Name:',
                  child: FcTextField(
                    controller: _name,
                    autofocus: true,
                    hintText: 'Directory name',
                    // Имя задаётся по мере ввода, а не при подтверждении: Enter
                    // обрабатывает ядро, и к моменту execute параметр уже
                    // должен быть на месте.
                    onChanged: (value) => setParam(nameParam, value),
                    onSubmitted: (_) => submit(),
                  ),
                ),
                SizedBox(height: FcTheme.of(context).metrics.dialogGap),
                CommandDialogField(
                  label: 'Inside:',
                  child: Text(
                    _parentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FcTheme.of(context).dialogTextStyle,
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// Каталог, в котором появится новый: показывается в окне.
  String get _parentPath {
    final panel = context.panel;
    final directory = panel.directory;
    return directory?.pathString ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}

/// Удаление выбранных объектов в корзину.
class RemoveCommand extends RemoveCommandBase {
  @override
  String get id => 'file.remove';

  @override
  String get label => 'Delete';

  @override
  bool get toTrash => true;
}

/// Удаление выбранных объектов мимо корзины.
///
/// Отдельная команда, а не параметр [RemoveCommand]: поведение разное,
/// и в списке команд это должно быть видно.
class RemovePermanentlyCommand extends RemoveCommandBase {
  @override
  String get id => 'file.removePermanently';

  @override
  String get label => 'Delete permanently';

  @override
  bool get toTrash => false;
}

/// Общий ход удаления.
///
/// [execute] удаляет без вопросов — так его вызовет сценарий. Окно добавляет
/// к этому подтверждение перед началом и показывает ход работы.
///
/// Реализует [AsyncCommand]: прогресс виден и снаружи окна — это задел на
/// фоновое выполнение, когда операции будут показываться общим списком.
abstract class RemoveCommandBase extends AsyncCommandBase {
  /// Куда девается объект: в корзину или совсем.
  bool get toTrash;

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    if (panel.busy || panel.editor == null) {
      return false;
    }
    // Псевдоузел «..» объектом не считается.
    return context.targets.any((node) => node is! ParentDirNode);
  }

  /// Объекты, с которыми работает команда: помеченные или тот, что под курсором.
  List<FsNode> get targets => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute() async {
    final panel = context.panel;
    final editor = panel.editor;
    final targets = this.targets;
    if (editor == null || targets.isEmpty || isRunning) {
      return;
    }

    try {
      await runOperation(editor.remove(targets, toTrash: toTrash), message: 'Deleting…');
    } finally {
      // Часть объектов могла исчезнуть, часть остаться: список в панели больше
      // не совпадает с диском.
      panel.selection.clear();
      await panel.reload();
    }
  }

  // --- окно ---

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) {
        final question = this.question;
        if (question != null) {
          return CommandDialogQuestion(message: question.message, options: question.options, onAnswer: answer);
        }
        if (isRunning) {
          return CommandDialogProgress(
            progress: progress,
            message: progressMessage,
            processed: processed,
            total: total,
            totalIsFinal: totalIsFinal,
            onCancel: cancel,
          );
        }
        final failure = error;
        if (failure != null) {
          return CommandDialogConfirm(
            message: 'Delete failed',
            error: failure,
            confirmLabel: 'Close',
            onCancel: dismiss,
            onConfirm: dismiss,
          );
        }

        return CommandDialogConfirm(
          message: _confirmationMessage,
          confirmLabel: toTrash ? 'Delete' : 'Delete permanently',
          onCancel: dismiss,
          onConfirm: submit,
        );
      },
    );
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  @override
  String get dialogTitle => '$label $_what';

  String get _what {
    final targets = this.targets;
    return targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
  }

  String get _confirmationMessage =>
      toTrash ? 'Move $_what to Trash?' : 'Delete $_what permanently? This cannot be undone.';
}
