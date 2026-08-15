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
