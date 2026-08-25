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

  static const String commandId = 'file.mkdir';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Dir';

  @override
  String get description => 'Create a directory in the active panel';

  /// В заголовке места больше, чем на кнопке в ряду, где стоит сжатое «Mk Dir».
  String get dialogTitle => 'Make directory';

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    // Провайдер может уметь только читать — тогда создавать нечем.
    return !panel.busy && panel.directory != null && panel.editor != null;
  }

  /// Создать каталог — или сперва спросить, как его назвать.
  ///
  /// Имя задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final parent = panel.directory;
    final editor = panel.editor;
    if (parent == null || editor == null) {
      return;
    }

    Future<void> create(String name) async {
      final created = await editor.makeDirectory(parent, name).result;
      // Каталог создан на диске, но в панели его ещё нет: перечитываем и
      // ставим курсор на новый каталог, чтобы с ним можно было сразу работать.
      await panel.reload();
      panel.setCursorToName(created.name);
    }

    // «Задано» — значит параметр есть, а не «есть и непустой»: пробелы это
    // заданное имя, просто негодное.
    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      final trimmed = given.trim();
      if (trimmed.isEmpty) {
        throw const FsError('', FsErrorKind.invalidName);
      }
      await create(trimmed);
      return;
    }

    final view = context.app.view;
    final state = MakeDirectoryDialogState(parentPath: _parentPath, create: create);

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        takesFocus: true,
        content: _MakeDirectoryForm(state: state),
        onSubmit: state.submit,
        onDismiss: state.close,
      ),
    );
  }

  /// Каталог, в котором появится новый: показывается в окне.
  String get _parentPath {
    final panel = context.panel;
    final directory = panel.directory;
    return directory?.displayPath ?? '';
  }
}

/// Что набрано в окне создания каталога и что из этого вышло.
///
/// Живёт, пока открыто окно: команда, показав его, уходит. Ошибка остаётся
/// здесь же — имя правят тут же, а не набирают заново.
class MakeDirectoryDialogState extends ChangeNotifier {
  MakeDirectoryDialogState({required this.parentPath, required this.create});

  /// Каталог, в котором появится новый. Не редактируется, но показывается
  /// таким же полем — как в референсе.
  final String parentPath;

  final Future<void> Function(String name) create;

  String name = '';
  String? error;

  /// Чем закрыть себя; null — окно ещё не показано (так бывает в тесте).
  VoidCallback? close;

  Future<void> submit() async {
    error = null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      error = const FsError('', FsErrorKind.invalidName).message;
      notifyListeners();
      return;
    }

    try {
      await create(trimmed);
      close?.call();
    } on FsError catch (failure) {
      error = failure.message;
      notifyListeners();
    }
  }
}

/// Два поля — куда и как назвать — и две кнопки.
class _MakeDirectoryForm extends StatefulWidget {
  const _MakeDirectoryForm({required this.state});

  final MakeDirectoryDialogState state;

  @override
  State<_MakeDirectoryForm> createState() => _MakeDirectoryFormState();
}

class _MakeDirectoryFormState extends State<_MakeDirectoryForm> {
  late final TextEditingController _inside = TextEditingController(text: widget.state.parentPath);
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _inside.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder:
          (context, _) => CommandDialogForm(
            error: state.error,
            onCancel: state.close ?? () {},
            onSubmit: state.submit,
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
                      onChanged: (value) => state.name = value,
                      onSubmitted: (_) => state.submit(),
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
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
abstract class RemoveCommandBase extends AppCommand {
  /// Согласие удалять, заданное заранее: сценарию спрашивать некого.
  static const String confirmedParam = 'confirmed';

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

  /// «Delete !» в заголовке разбора читалось бы как опечатка: восклицательный
  /// знак в названии команды отличает её от удаления в корзину, а не от чего-то
  /// ещё.
  String get failureMessage => 'Delete failed';

  /// Спросить, точно ли удалять, — и удалить.
  ///
  /// Команда показывает окно и уходит: всё, что живёт дальше — подтверждение,
  /// ход работы, вопросы по дороге, уход в фон, — принадлежит окну.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final editor = panel.editor;
    final targets = this.targets;
    if (editor == null || targets.isEmpty) {
      return;
    }

    Future<void> remove() async {
      // Аренда — на всё время работы: удаление можно отправить в фон, и панель
      // за это время вправе выйти из архива, в котором оно идёт.
      final source = panel.leaseProvider();
      try {
        await editor.remove(targets, toTrash: toTrash).result;
      } finally {
        await source?.release();
        // Часть объектов могла исчезнуть, часть остаться: список в панели
        // больше не совпадает с диском.
        panel.selection.clear();
        await panel.reload();
      }
    }

    if (context.invocation.param<bool>(confirmedParam) == true) {
      // Согласие уже дано — спрашивать некого и незачем.
      await remove();
      return;
    }

    final view = context.app.view;
    late final FcAsyncRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: dialogTitle,
          takesFocus: true,
          // Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
          // длительных работ, их берёт на себя окно. Своё здесь только одно:
          // спросить, точно ли удалять.
          content: FcAsyncRunDialog(
            run: run,
            form:
                (context) => CommandDialogConfirm(
                  message: _confirmationMessage,
                  confirmLabel: toTrash ? 'Delete' : 'Delete permanently',
                  onCancel: run.dismiss,
                  onConfirm: run.submit,
                ),
          ),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = FcAsyncRun(
      app: context.app,
      commandId: id,
      title: dialogTitle,
      failureMessage: failureMessage,
      show: present,
    );

    run.onStart = () async {
      final source = panel.leaseProvider();
      try {
        await run.run(editor.remove(targets, toTrash: toTrash), message: 'Deleting…');
      } finally {
        await source?.release();
        panel.selection.clear();
        await panel.reload();
      }
    };

    present();
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  String get dialogTitle => '$label $_what';

  String get _what {
    final targets = this.targets;
    return targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
  }

  String get _confirmationMessage =>
      toTrash ? 'Move $_what to Trash?' : 'Delete $_what permanently? This cannot be undone.';
}
