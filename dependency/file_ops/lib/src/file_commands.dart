import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Создание каталога в активной панели.
///
/// Работает и без интерфейса: задать имя параметром и вызвать [execute].
/// Окно — надстройка: оно задаёт тот же параметр и вызывает тот же [execute].
class MakeDirectoryCommand extends AppCommand {
  /// Имя нового каталога.
  static const String nameParam = 'name';

  final TextEditingController _name = TextEditingController();

  /// Каталог, в котором появится новый. Не редактируется, но показывается таким
  /// же полем — как в референсе.
  final TextEditingController _inside = TextEditingController();

  static const String commandId = 'file.mkdir';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Dir';

  @override
  String get description => 'Create a directory in the active panel';

  @override
  bool get hasDialog => true;

  /// Имя набирают сразу: фокус ставит поле ввода.

  @override
  void attachRun({required String runId, required CommandContext context}) {
    super.attachRun(runId: runId, context: context);
    _inside.text = _parentPath;
  }

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
  DialogSpec? dialogSpec(BuildContext context) {
    return DialogSpec(
      title: dialogTitle,
      takesFocus: true,
      content: ListenableBuilder(
        listenable: this,
        builder:
            (context, _) => CommandDialogForm(
              error: error,
              onCancel: dismiss,
              onSubmit: submit,
              submitLabel: 'Create',
              // Поля те же, что в референсе: имя и каталог, в котором создаём.
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CommandDialogField(label: 'Inside', child: FcTextField(controller: _inside, enabled: false)),
                    SizedBox(height: FcTheme.of(context).metrics.dialogGap),
                    CommandDialogField(
                      label: 'Make directory',
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
                  ],
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
    return directory?.displayPath ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _inside.dispose();
    super.dispose();
  }
}

/// Удаление выбранных объектов в корзину.
class RemoveCommand extends RemoveCommandBase {
  static const String commandId = 'file.remove';

  @override
  String get id => commandId;

  @override
  String get label => 'Delete';

  @override
  String get description => 'Move the selected items to the trash';

  @override
  bool get toTrash => true;
}

/// Удаление выбранных объектов мимо корзины.
///
/// Отдельная команда, а не параметр [RemoveCommand]: поведение разное,
/// и в списке команд это должно быть видно.
class RemovePermanentlyCommand extends RemoveCommandBase {
  static const String commandId = 'file.removePermanently';

  @override
  String get id => commandId;

  @override
  String get label => 'Delete !';

  @override
  String get description => 'Delete the selected items without the trash';

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
    if (editor == null || targets.isEmpty || isBusy) {
      return;
    }

    // Аренда — на всё время работы: удаление можно отправить в фон, и панель
    // за это время вправе выйти из архива, в котором оно идёт.
    final source = panel.leaseProvider();

    try {
      await runOperation(editor.remove(targets, toTrash: toTrash), message: 'Deleting…');
    } finally {
      await source?.release();
      // Часть объектов могла исчезнуть, часть остаться: список в панели больше
      // не совпадает с диском.
      panel.selection.clear();
      await panel.reload();
    }
  }

  // --- окно ---

  /// Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
  /// длительных работ, их берёт на себя [AsyncCommandDialog]. Команде остаётся
  /// то, что у неё своё: спросить, точно ли удалять.
  @override
  DialogSpec? dialogSpec(BuildContext context) =>
      DialogSpec(title: dialogTitle, takesFocus: true, content: AsyncCommandDialog(command: this, form: _form));

  /// «Delete !» в заголовке разбора читалось бы как опечатка: восклицательный
  /// знак в названии команды отличает её от удаления в корзину, а не от чего-то
  /// ещё.
  @override
  String get failureMessage => 'Delete failed';

  Widget _form(BuildContext context) => CommandDialogConfirm(
    message: _confirmationMessage,
    confirmLabel: toTrash ? 'Delete' : 'Delete permanently',
    onCancel: dismiss,
    onConfirm: submit,
  );

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
