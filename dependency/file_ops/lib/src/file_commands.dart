import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
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
  String get label => tr('Mk Dir');

  @override
  String get description => tr('Create a directory in the active panel');

  /// «Folder» — то же самое словом другой школы, и набирают его не реже.
  @override
  Set<String> get keywords => const {'folder', 'directory', 'new folder', 'create'};

  /// В заголовке места больше, чем на кнопке в ряду, где стоит сжатое «Mk Dir».
  String get dialogTitle => tr('Make directory');

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    // Источник может уметь только читать — тогда создавать нечем.
    return !panel.busy && panel.currentPath.isNotEmpty && panel.source.canWrite;
  }

  /// Создать каталог — или сперва спросить, как его назвать.
  ///
  /// Имя задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final parent = panel.currentPath;
    if (parent.isEmpty || !panel.source.canWrite) {
      return;
    }

    Future<void> create(String name) async {
      await context.app.runOperation().run(
        OperationSpec(
          kind: FileOperations.makeDirectory,
          // Место называет панель — тем путём, который показывает сама: у
          // дерева это каталог строки под курсором, и ядро его не угадывает
          // (`docs/spec/client-server.md`, §5.6а).
          destination: Destination.inPanel(panel.id, path: parent),
          options: {FileOperations.name: name},
        ),
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
    return context.session.currentPath;
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
            submitLabel: context.strings.tr('Create'),
            // Поля те же, что в референсе: имя и каталог, в котором создаём.
            children: [
              CommandDialogField(
                label: context.strings.tr('Inside'),
                child: FcTextField(controller: _inside, enabled: false),
              ),
              CommandDialogField(
                label: context.strings.tr('Make directory'),
                child: FcTextField(
                  controller: _name,
                  autofocus: true,
                  hintText: context.strings.tr('Directory name'),
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
  String get label => tr('Delete');

  @override
  String get description => tr('Move the selected items to the trash');

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
  String get label => tr('Delete !');

  @override
  String get description => tr('Delete the selected items without the trash');

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
  /// Имя окна, когда мимо корзины уходит часть: под ним помнятся его размер и
  /// место (`docs/spec/trash-unavailable.md`, §4б). Внешний контракт — оно
  /// лежит в `settings.json`.
  static const String untrashableDialogId = 'file.remove.untrashable';

  /// Согласие удалять, заданное заранее: сценарию спрашивать некого.
  static const String confirmedParam = 'confirmed';

  /// Куда девается объект: в корзину или совсем.
  bool get toTrash;

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    if (panel.busy || !panel.source.canWrite) {
      return false;
    }
    // Помеченное считается **всё**, где бы оно ни лежало: пометить можно и из
    // дерева, в соседней ветви (`docs/spec/operation-targets.md`, §1).
    return panel.hasTargets;
  }

  /// Объекты, с которыми работает команда: помеченные или тот, что под
  /// курсором.
  ///
  /// Именем набора, а не перечислением: разворачивает его ядро — пометка живёт
  /// там же, где дерево.
  Targets targetsOf(CommandContext context) => Targets.marked(context.session.id, under: context.session.currentRef);

  /// «Delete !» в заголовке разбора читалось бы как опечатка: восклицательный
  /// знак в названии команды отличает её от удаления в корзину, а не от чего-то
  /// ещё.
  String get failureMessage => tr('Delete failed');

  /// Спросить, точно ли удалять, — и удалить.
  ///
  /// Команда показывает окно и уходит: всё, что живёт дальше — подтверждение,
  /// ход работы, вопросы по дороге, уход в фон, — принадлежит окну.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    if (!panel.source.canWrite || !panel.hasTargets) {
      return;
    }

    // Аренду на время работы берёт ядро: удаление можно отправить в фон, и
    // панель за это время вправе выйти из архива, в котором оно идёт. Держать
    // источник живым — дело той стороны, где он и живёт.
    //
    // Сколько целей в корзину не уйдёт: null — ядро ещё не ответило. Окно
    // встаёт, не дожидаясь, и меняет слова, когда ответ придёт: согласие,
    // данное на «удалить навсегда», второй раз по ходу работы не спрашивают
    // (`docs/spec/trash-unavailable.md`).
    final untrashable = ValueNotifier<({List<FileEntry> rows, int count})?>(
      toTrash ? null : (rows: const <FileEntry>[], count: 0),
    );
    OperationSpec specOf() => OperationSpec(
      kind: FileOperations.remove,
      targets: targetsOf(context),
      options: {
        FileOperations.toTrash: toTrash,
        if (toTrash && (untrashable.value?.count ?? 0) > 0) FileOperations.withoutTrash: true,
      },
    );
    final spec = specOf();

    // Каталоги, из которых удаляют. Спрашиваются **до** работы: после неё
    // объектов уже нет, и спросить их каталог будет не у кого
    // (`docs/spec/operation-targets.md`, §6).
    final sources = <String>{};
    Future<void> askSources() async {
      sources.addAll({for (final entry in await panel.allTargets()) entry.directoryPath});
    }

    Future<void> remove() async {
      try {
        await context.app.runOperation().run(spec);
      } finally {
        // Часть объектов могла исчезнуть, часть остаться: список в панели
        // больше не совпадает с диском.
        panel.clearMarks(by: MarkChange.work);
        await reloadPanelsAt(context.app, [...sources, panel.currentPath]);
      }
    }

    if (context.invocation.param<bool>(confirmedParam) == true) {
      // Согласие уже дано — спрашивать некого и незачем.
      await askSources();
      await remove();
      return;
    }

    final view = context.app.view;
    // Считается до окна: внутри `form` в имени `context` уже BuildContext.
    final what = _whatOf(context);
    final app = context.app;
    final total = context.session.targetPaths.length;
    // Один раз: `present` зовут ещё и при возврате работы из фона, а пометку к
    // тому времени уже сняли.
    final title = titleOf(context);
    late final FcAsyncRun run;

    // Мимо корзины уйдёт часть — список деревом (§4а).
    bool listedNow() {
      final count = untrashable.value?.count ?? 0;
      return count > 0 && count < total;
    }

    // Окно стоит и ещё не закрыто: подменить его есть что.
    var open = false;

    void present() {
      late final String dialogId;
      run.close = () {
        open = false;
        view.closeDialog(dialogId);
      };
      // Тянется и помнит размер только окно со списком: у вопроса в две строки
      // тянуть нечего, а запомненная высота списка растянула бы и его
      // (`docs/spec/trash-unavailable.md`, §4б).
      final listed = listedNow();
      open = true;
      dialogId = view.showDialog(
        DialogSpec(
          title: title,
          id: listed ? untrashableDialogId : null,
          resizable: listed,
          // Со списком ширину назначает окно само, долей экрана, как у находок:
          // ленивый список о своей ширине не отвечает.
          ownWidth: listed,
          takesFocus: true,
          // Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
          // длительных работ, их берёт на себя окно. Своё здесь только одно:
          // спросить, точно ли удалять.
          content: FcAsyncRunDialog(
            run: run,
            form:
                (_) => ValueListenableBuilder<({List<FileEntry> rows, int count})?>(
                  valueListenable: untrashable,
                  builder: (context, untrashed, _) {
                    final count = untrashed?.count ?? 0;
                    // Списком — только когда мимо корзины уйдёт **часть**: про
                    // всё сразу говорит сама фраза, а выбранное из разных
                    // ветвей дерева иначе не назвать.
                    final listed = count > 0 && count < total;
                    final confirm = CommandDialogConfirm(
                      message: _confirmationMessageOf(what, untrashable: count, total: total),
                      confirmLabel: toTrash && count < total ? tr('Delete') : tr('Delete permanently'),
                      fields: [
                        if (listed)
                          CommandDialogField.wide(
                            // Растянули окно — прибавка достаётся списку: ради
                            // него и тянут.
                            expands: true,
                            child: _UntrashableTree(app: app, panel: panel.id, rows: untrashed!.rows),
                          ),
                      ],
                      onCancel: run.dismiss,
                      onConfirm: run.submit,
                    );
                    if (!listed) {
                      return confirm;
                    }
                    // Ширина — доля экрана, как у находок поиска: пути длинные и
                    // разные, и окно, облегающее их, прыгало бы.
                    final factor = FcTheme.of(context).metrics.paletteWidthFactor;
                    return SizedBox(width: MediaQuery.sizeOf(context).width * factor, child: confirm);
                  },
                ),
          ),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = FcAsyncRun(app: context.app, commandId: id, title: title, failureMessage: failureMessage, show: present);

    run.onStart = () async {
      try {
        // Собирается в миг согласия: что сказало окно, то работа и знает.
        await run.run(context.app.runOperation(), specOf(), message: tr('Deleting…'));
      } finally {
        panel.clearMarks(by: MarkChange.work);
        await reloadPanelsAt(context.app, [...sources, panel.currentPath]);
      }
    };

    present();
    // Окно уже стоит — теперь можно и спросить, откуда цели: ждать оборот
    // границы до показа значит оставить щель для удержанной клавиши
    // (`docs/spec/operation-targets.md`, §2).
    unawaited(askSources());
    if (toTrash) {
      unawaited(
        panel.untrashableTargets().then((found) {
          untrashable.value = found;
          // Окно встало раньше ответа и тянуться не умеет: раз список нужен,
          // оно подменяется тянущимся. Только пока не ответили — идущую работу
          // окном не трогают.
          if (open && listedNow() && !run.isBusy) {
            run.close?.call();
            present();
          }
        }),
      );
    }
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  String titleOf(CommandContext context) => '$label ${_whatOf(context)}';

  /// Считается по **путям** целей, а не по строкам списка: помеченное бывает из
  /// разных каталогов, и подтверждение, обещающее удалить два, а стирающее
  /// пять, — худший случай этой лжи (`docs/spec/operation-targets.md`, §1).
  String _whatOf(CommandContext context) {
    final paths = context.session.targetPaths;
    if (paths.length == 1) {
      final path = paths.single;
      final seen = context.session.entries.where((entry) => entry.path == path).firstOrNull;
      return '«${seen?.name ?? _nameOf(path)}»';
    }
    return plural(paths.length, one: '{n} item', other: '{n} items');
  }

  /// Имя объекта из пути: у помеченного в соседней ветви значения по эту
  /// сторону не лежит.
  static String _nameOf(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// [untrashable] — сколько из [total] целей в корзину не уйдёт: о них окно
  /// говорит прямо, а не оставляет вопросу по ходу работы.
  String _confirmationMessageOf(String what, {required int untrashable, required int total}) {
    if (!toTrash) {
      return tr('Delete {what} permanently? This cannot be undone.', args: {'what': what});
    }
    if (untrashable == 0) {
      return tr('Move {what} to Trash?', args: {'what': what});
    }
    if (untrashable >= total) {
      return tr('{what} cannot be moved to Trash. Delete permanently? This cannot be undone.', args: {'what': what});
    }
    final rest = plural(
      untrashable,
      one: '{n} of them cannot be moved there and will be deleted permanently:',
      other: '{n} of them cannot be moved there and will be deleted permanently:',
    );
    return '${tr('Move {what} to Trash?', args: {'what': what})} $rest';
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
  String get label => tr('Rename');

  @override
  String get description => tr('Rename the item under the cursor');

  /// «name» в синонимах нет: оно и так внутри названия, а сторож в списке
  /// команд справедливо считает такие слова мёртвым грузом. «move» — есть:
  /// переименование ищут там же, где перенос, и найти стоит оба.
  @override
  Set<String> get keywords => const {'change name', 'move'};

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
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
    final panel = context.session;
    final entry = context.entry;
    if (entry == null || entry.isParent || !panel.source.canWrite) {
      return;
    }

    // Строка называется **сейчас**, до окна с именем: переименовывают ту, на
    // которой стоял человек, когда нажал, — а не ту, где к концу разговора
    // окажется чей-то курсор (`docs/spec/client-server.md`, §5.6).
    final row = panel.currentRef;
    if (row == null) {
      return;
    }

    Future<void> rename(String name) async {
      await context.app.runOperation().run(
        OperationSpec(kind: FileOperations.rename, targets: Targets.row(row), options: {FileOperations.name: name}),
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
        title: tr('Rename'),
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
            submitLabel: context.strings.tr('Rename'),
            children: [
              CommandDialogField(
                label: context.strings.tr('New name'),
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

/// То, что уйдёт мимо корзины, — сжатым деревом, на плашке, как находки
/// поиска (`docs/spec/trash-unavailable.md`, §4а): видно, из какой ветви
/// каждый объект.
///
/// Вид — стандартный, из реестра видов панели; рисует он снимок, а не панель:
/// ни вкладки, ни источника у списка нет. Только для чтения — решение одно на
/// весь список.
class _UntrashableTree extends StatefulWidget {
  const _UntrashableTree({required this.app, required this.panel, required this.rows});

  final Application app;
  final PanelId panel;

  /// Строки дерева, как их сложило ядро: у него узлы и их настоящие каталоги.
  final List<FileEntry> rows;

  @override
  State<_UntrashableTree> createState() => _UntrashableTreeState();
}

class _UntrashableTreeState extends State<_UntrashableTree> {
  /// Меньше — и это уже не список: столько строк видно всегда.
  static const int _minRows = 4;

  late final SnapshotSession _snapshot = SnapshotSession(id: widget.panel, entries: widget.rows);

  /// Фокус списка: по `Tab` и щелчку, как у находок поиска.
  final FocusNode _focus = FocusNode(debugLabel: 'untrashable tree');

  @override
  void dispose() {
    _focus.dispose();
    _snapshot.dispose();
    super.dispose();
  }

  /// Стрелки, страницы и края водят курсор по снимку.
  ///
  /// Ловит их список, а не реестр команд: пока окно открыто, клавиши
  /// принадлежат ему (`screens.md`). Автоповтор — наравне с нажатием: удержание
  /// стрелки обязано вести курсор, как в панели и в находках.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _snapshot.moveCursor(1);
      case LogicalKeyboardKey.arrowUp:
        _snapshot.moveCursor(-1);
      case LogicalKeyboardKey.pageDown:
        _snapshot.moveCursorPage(1);
      case LogicalKeyboardKey.pageUp:
        _snapshot.moveCursorPage(-1);
      case LogicalKeyboardKey.home:
        _snapshot.setCursorToFirst();
      case LogicalKeyboardKey.end:
        _snapshot.setCursorToLast();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final views = widget.app.panelViews;
    final spec = views.byId(_snapshot.view) ?? views.available.firstOrNull;
    // Своя высота — пока окно не растянули: треть экрана, но не меньше четырёх
    // строк и заголовка вида. Растянули — высоту назначает рама, и поле со
    // списком берёт её целиком (`docs/spec/dialog-resize.md`, §6).
    final step = theme.metrics.rowHeight;
    final third = MediaQuery.sizeOf(context).height / 3;
    final least = (_minRows + 1) * step;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: ListenableBuilder(
          listenable: _focus,
          // Курсор светится, только когда клавиши у списка: иначе он обещал бы
          // стрелкам то, что у них заберёт кнопка.
          builder:
              (context, child) =>
                  KeysScope(takesKeys: _focus.hasFocus && (KeysScope.maybeOf(context) ?? true), child: child!),
          child: FcPlate(
            tight: true,
            child: SizedBox(
              height: third > least ? third : least,
              child: spec == null ? const SizedBox.shrink() : spec.build(context, _snapshot),
            ),
          ),
        ),
      ),
    );
  }
}
