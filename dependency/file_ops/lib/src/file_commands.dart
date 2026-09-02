import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'panels_at.dart';

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

  /// «Folder» — то же самое словом другой школы, и набирают его не реже.
  @override
  Set<String> get keywords => const {'folder', 'directory', 'new folder', 'create'};

  /// В заголовке места больше, чем на кнопке в ряду, где стоит сжатое «Mk Dir».
  String get dialogTitle => 'Make directory';

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    // Источник может уметь только читать — тогда создавать нечем.
    return !panel.busy && panel.path.isNotEmpty && panel.source.canWrite;
  }

  /// Создать каталог — или сперва спросить, как его назвать.
  ///
  /// Имя задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final parent = panel.path;
    if (parent.isEmpty || !panel.source.canWrite) {
      return;
    }

    Future<void> create(String name) async {
      await context.app.runOperation().run(
        OperationSpec(kind: FileOperations.makeDirectory, destination: panel.id, options: {FileOperations.name: name}),
      );
      // Каталог создан на диске, но в панели его ещё нет: перечитываем и
      // ставим курсор на новый каталог, чтобы с ним можно было сразу работать.
      // Перечитываются **обе** панели, если обе стоят здесь же: вторая тоже
      // смотрит на этот каталог.
      await reloadPanelsAt(context.app, [parent]);
      panel.setCursorToName(name);
    }

    // «Задано» — значит параметр есть, а не «есть и непустой»: пробелы это
    // заданное имя, просто негодное.
    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      final trimmed = trimmedFileName(given);
      if (trimmed.isEmpty) {
        throw const FsError('', FsErrorKind.invalidName);
      }
      await create(trimmed);
      return;
    }

    final view = context.app.view;
    final state = MakeDirectoryDialogState(parentPath: _parentPathOf(context), create: create);

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
  String _parentPathOf(CommandContext context) {
    return context.panel.path;
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
    // Края имени и края основы — по одному правилу с переименованием: два
    // окна, спрашивающих имя, обязаны понимать его одинаково.
    final trimmed = trimmedFileName(name);
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
              CommandDialogField(label: 'Inside', child: FcTextField(controller: _inside, enabled: false)),
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

  /// `rm` — привычка из терминала; «trash» и «bin» — то, куда объекты уходят.
  @override
  Set<String> get keywords => const {'remove', 'trash', 'bin', 'erase', 'rm'};

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

  /// Ищут её обычно словами про необратимость, а не по имени.
  @override
  Set<String> get keywords => const {'remove', 'erase', 'permanently', 'no trash', 'shred'};

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
    if (panel.busy || !panel.source.canWrite) {
      return false;
    }
    // Псевдострока «..» объектом не считается.
    return context.targets.any((entry) => !entry.isParent);
  }

  /// Объекты, с которыми работает команда: помеченные или тот, что под
  /// курсором.
  ///
  /// Именем набора, а не перечислением: разворачивает его ядро — пометка живёт
  /// там же, где дерево.
  Targets targetsOf(CommandContext context) => Targets.marked(context.panel.id);

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
    if (!panel.source.canWrite || context.targets.every((entry) => entry.isParent)) {
      return;
    }

    // Аренду на время работы берёт ядро: удаление можно отправить в фон, и
    // панель за это время вправе выйти из архива, в котором оно идёт. Держать
    // источник живым — дело той стороны, где он и живёт.
    final spec = OperationSpec(
      kind: FileOperations.remove,
      targets: targetsOf(context),
      options: {FileOperations.toTrash: toTrash},
    );

    Future<void> remove() async {
      try {
        await context.app.runOperation().run(spec);
      } finally {
        // Часть объектов могла исчезнуть, часть остаться: список в панели
        // больше не совпадает с диском.
        panel.clearMarks();
        await reloadPanelsAt(context.app, [panel.path]);
      }
    }

    if (context.invocation.param<bool>(confirmedParam) == true) {
      // Согласие уже дано — спрашивать некого и незачем.
      await remove();
      return;
    }

    final view = context.app.view;
    // Считается до окна: внутри `form` в имени `context` уже BuildContext.
    final confirmation = _confirmationMessageOf(context);
    late final FcAsyncRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: titleOf(context),
          takesFocus: true,
          // Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
          // длительных работ, их берёт на себя окно. Своё здесь только одно:
          // спросить, точно ли удалять.
          content: FcAsyncRunDialog(
            run: run,
            form:
                (_) => CommandDialogConfirm(
                  message: confirmation,
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
      title: titleOf(context),
      failureMessage: failureMessage,
      show: present,
    );

    run.onStart = () async {
      try {
        await run.run(context.app.runOperation(), spec, message: 'Deleting…');
      } finally {
        panel.clearMarks();
        await reloadPanelsAt(context.app, [panel.path]);
      }
    };

    present();
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  String titleOf(CommandContext context) => '$label ${_whatOf(context)}';

  String _whatOf(CommandContext context) {
    final targets = [
      for (final entry in context.targets)
        if (!entry.isParent) entry,
    ];
    return targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
  }

  String _confirmationMessageOf(CommandContext context) {
    final what = _whatOf(context);
    return toTrash ? 'Move $what to Trash?' : 'Delete $what permanently? This cannot be undone.';
  }
}

/// Переименование объекта под курсором.
///
/// Отдельная команда, а не свойство переноса: у `F6` приёмником может быть
/// только каталог, и другого имени ему не задать. Поэтому переименования в
/// приложении не было вовсе — а примитив у провайдеров был давно
/// (`spec/rename.md`).
class RenameCommand extends AppCommand {
  /// Новое имя.
  static const String nameParam = 'name';

  static const String commandId = 'file.rename';

  @override
  String get id => commandId;

  @override
  String get label => 'Rename';

  @override
  String get description => 'Rename the item under the cursor';

  /// «name» в синонимах нет: оно и так внутри названия, а сторож в списке
  /// команд справедливо считает такие слова мёртвым грузом. «move» — есть:
  /// переименование ищут там же, где перенос, и найти стоит оба.
  @override
  Set<String> get keywords => const {'change name', 'move'};

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    if (panel.busy || !panel.source.canWrite) {
      return false;
    }
    // Переименовать можно только то, что провайдер умеет переименовывать одним
    // действием: в архиве за этим пряталась бы пересборка целиком, а о ней
    // полагается спрашивать (`spec/rename.md`, §4).
    if (!panel.source.capabilities.canRename) {
      return false;
    }
    final entry = context.entry;
    // «..» — не объект, а способ выйти наверх.
    return entry != null && !entry.isParent;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final entry = context.entry;
    if (entry == null || entry.isParent || !panel.source.canWrite) {
      return;
    }

    Future<void> rename(String name) async {
      await context.app.runOperation().run(
        OperationSpec(
          kind: FileOperations.rename,
          targets: Targets.current(panel.id),
          options: {FileOperations.name: name},
        ),
      );
      // Объект на месте, но в панели ещё под прежним именем: перечитываем и
      // ищем его по **новому** — иначе курсор прыгает в начало ровно тогда,
      // когда человек смотрит на результат. Вторая панель, стоящая здесь же,
      // показывала бы прежнее имя, поэтому перечитываются обе.
      await reloadPanelsAt(context.app, [entry.directoryPath]);
      panel.setCursorToName(name);
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await rename(given);
      return;
    }

    final view = context.app.view;
    final state = RenameDialogState(original: entry.name, rename: rename);

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: 'Rename',
        takesFocus: true,
        content: _RenameForm(state: state),
        onSubmit: state.submit,
        onDismiss: state.close,
      ),
    );
  }
}

/// Что набрано в окне переименования и что из этого вышло.
class RenameDialogState extends ChangeNotifier {
  RenameDialogState({required this.original, required this.rename}) : name = original;

  /// Имя, с которого начали: в поле оно уже стоит.
  final String original;

  final Future<void> Function(String name) rename;

  String name;
  String? error;

  VoidCallback? close;

  Future<void> submit() async {
    error = null;
    final trimmed = trimmedFileName(name);
    if (trimmed.isEmpty) {
      error = const FsError('', FsErrorKind.invalidName).message;
      notifyListeners();
      return;
    }
    if (trimmed == original) {
      // Имя не менялось: закрываем окно, работы нет.
      close?.call();
      return;
    }

    try {
      await rename(trimmed);
      close?.call();
    } on FsError catch (failure) {
      // Ошибка остаётся здесь же: имя правят тут же, а не набирают заново.
      error = failure.message;
      notifyListeners();
    }
  }
}

/// Поле с именем — и выделенной основой.
class _RenameForm extends StatefulWidget {
  const _RenameForm({required this.state});

  final RenameDialogState state;

  @override
  State<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends State<_RenameForm> {
  late final TextEditingController _name = TextEditingController(text: widget.state.original)
    ..selection = _baseSelection(widget.state.original);

  /// Выделяется основа без расширения: правят обычно её, а `.tar.gz`
  /// дописывать по десятому разу обидно. Где кончается основа, решает то же
  /// правило, что рисует колонку расширения.
  static TextSelection _baseSelection(String name) {
    final (:base, :extension) = const ReferenceFileNaming().split(name);
    return TextSelection(baseOffset: 0, extentOffset: extension.isEmpty ? name.length : base.length);
  }

  @override
  void dispose() {
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
            submitLabel: 'Rename',
            children: [
              CommandDialogField(
                label: 'New name',
                child: FcTextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (value) => state.name = value,
                  onSubmitted: (_) => state.submit(),
                ),
              ),
            ],
          ),
    );
  }
}
