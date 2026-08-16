import 'dart:async';

import '../../model/async/async_operation.dart';
import '../../model/tree/fs_node.dart';
import '../../model/tree/tree_provider.dart';
import 'app_command.dart';

/// Создание каталога в активной панели.
///
/// Первая настоящая файловая операция. Имя спрашивается через
/// [Application.dialogs], сам каталог создаёт [TreeEditor] — команда не знает
/// ни о виджетах, ни о файловой системе.
class MakeDirectoryCommand extends AppCommand {
  @override
  String get id => 'file.mkdir';

  @override
  String get label => 'Mk Dir';

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    // Провайдер может уметь только читать — тогда создавать нечем.
    return !panel.busy && panel.directory != null && panel.editor != null;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final parent = panel.directory;
    final editor = panel.editor;
    if (parent == null || editor == null) {
      return;
    }

    final name = await context.app.dialogs.promptText(
      title: 'Create directory',
      hint: 'Directory name',
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty) {
      // Пользователь отказался — молча выходим.
      return;
    }

    try {
      final created = await editor.makeDirectory(parent, name.trim()).result;
      // Каталог создан на диске, но в панели его ещё нет: перечитываем и
      // ставим курсор на новый каталог, чтобы с ним можно было сразу работать.
      await panel.reload();
      panel.setCursorToName(created.name);
    } on FsError catch (error) {
      await context.app.dialogs.showError(title: 'Cannot create directory', message: error.message);
    }
  }
}

/// Удаление выбранных объектов в корзину.
class RemoveCommand extends AppCommand {
  @override
  String get id => 'file.remove';

  @override
  String get label => 'Delete';

  @override
  bool isExecutable(CommandContext context) => canRemove(context);

  @override
  Future<void> execute(CommandContext context) => removeTargets(context, toTrash: true);
}

/// Удаление выбранных объектов мимо корзины.
///
/// Отдельная команда, а не параметр [RemoveCommand]: поведение разное,
/// и в списке команд это должно быть видно.
class RemovePermanentlyCommand extends AppCommand {
  @override
  String get id => 'file.removePermanently';

  @override
  String get label => 'Delete permanently';

  @override
  bool isExecutable(CommandContext context) => canRemove(context);

  @override
  Future<void> execute(CommandContext context) => removeTargets(context, toTrash: false);
}

/// Есть ли что удалять: псевдоузел «..» объектом не считается.
bool canRemove(CommandContext context) {
  final panel = context.panel;
  if (panel.busy || panel.editor == null) {
    return false;
  }
  return context.targets.any((node) => node is! ParentDirNode);
}

/// Общий ход удаления: спросить, удалить, перечитать панель.
///
/// Вынесено отдельно, потому что обе команды делают одно и то же и отличаются
/// только тем, куда девается объект.
Future<void> removeTargets(CommandContext context, {required bool toTrash}) async {
  final panel = context.panel;
  final editor = panel.editor;
  final targets = context.targets.where((node) => node is! ParentDirNode).toList();
  if (editor == null || targets.isEmpty) {
    return;
  }

  final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
  final confirmed = await context.app.dialogs.confirm(
    title: toTrash ? 'Delete' : 'Delete permanently',
    message: toTrash ? 'Move $what to Trash?' : 'Delete $what permanently? This cannot be undone.',
    confirmLabel: 'Delete',
  );
  if (!confirmed) {
    return;
  }

  final operation = editor.remove(targets, toTrash: toTrash);

  // Операция спрашивает по ходу дела: что делать с объектом, который не
  // удалился. Ответ приходит от пользователя тем же путём, что и остальные
  // диалоги.
  final requests = operation.requests.listen((request) async {
    final answer = await context.app.dialogs.chooseOption(
      title: toTrash ? 'Cannot delete' : 'Cannot delete permanently',
      message: request.message,
      options: request.options,
    );
    request.respond(answer ?? request.defaultOption);
  });

  try {
    await operation.result;
  } on OperationCanceled {
    // Пользователь прервал удаление: то, что уже удалено, останется удалённым.
  } on FsError catch (error) {
    await context.app.dialogs.showError(title: 'Delete failed', message: error.message);
  } finally {
    // Ответы больше не нужны; ждать завершения отписки незачем — это лишний
    // виток перед тем, как панель обновится.
    unawaited(requests.cancel());
  }

  // Часть объектов могла исчезнуть, часть остаться: список в панели больше
  // не совпадает с диском.
  panel.selection.clear();
  await panel.reload();
}
