import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Копирование выбранных объектов в другой каталог.
class CopyCommand extends TransferCommandBase {
  static const String commandId = 'file.copy';

  @override
  String get id => commandId;

  @override
  String get label => 'Copy';

  @override
  String get description => 'Copy the selected items to the other panel';

  @override
  bool get moves => false;
}

/// Перенос выбранных объектов в другой каталог.
///
/// Отдельная команда, а не параметр [CopyCommand]: у неё своя клавиша, своя
/// кнопка и своя строка в списке команд.
class MoveCommand extends TransferCommandBase {
  static const String commandId = 'file.move';

  @override
  String get id => commandId;

  @override
  String get label => 'Move';

  @override
  String get description => 'Move the selected items to the other panel';

  @override
  bool get moves => true;
}

/// Общий ход копирования и переноса.
///
/// Куда переносить — обычный параметр [destinationParam] со строкой пути.
/// По умолчанию это каталог пассивной панели: привычное поведение двухпанельного
/// менеджера. Значение можно заменить — из окна команды или откуда угодно ещё,
/// потому что путь берётся из параметра, а не из панели.
///
/// [execute] делает работу без вопросов о самом задании: что копировать и куда,
/// уже решено. Вопросы по ходу («такой файл уже есть») задаёт операция, и на них
/// отвечает окно, а если окна нет — берётся ответ по умолчанию.
abstract class TransferCommandBase extends AsyncCommandBase {
  /// Путь каталога, куда идёт работа.
  static const String destinationParam = 'destination';

  /// Идти ли по символическим ссылкам.
  ///
  /// По умолчанию нет — как в mc: ссылка переносится ссылкой. Приёмник,
  /// который так не умеет, вызывает вопрос: подменять ссылку её содержимым
  /// молча нельзя, это разные вещи и по размеру, и по смыслу.
  static const String followLinksParam = 'followLinks';

  /// Убирается ли исходный объект.
  bool get moves;

  final TextEditingController _destination = TextEditingController();

  /// Откуда идёт работа. Поле не редактируется — источник задан выбором в
  /// панели, — но остаётся полем: так форма читается как форма.
  final TextEditingController _source = TextEditingController();

  /// Путь набирают сразу: фокус ставит поле ввода.

  @override
  void attachRun({required String runId, required CommandContext context}) {
    super.attachRun(runId: runId, context: context);

    // Значение по умолчанию проставляется здесь, а не в окне: команду можно
    // выполнить и без окна, и тогда каталог пассивной панели остаётся
    // разумным ответом на вопрос «куда».
    final path = _defaultDestination;
    if (path != null) {
      setParam(destinationParam, path);
      _destination.text = path;
    }
    _source.text = _sourcePath;
  }

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    if (panel.busy) {
      return false;
    }
    // Принимать должен приёмник; терять объекты источник обязан только при
    // переносе — копировать из архива, открытого на просмотр, ничто не мешает.
    if (!context.target.provider.canWrite || (moves && !panel.provider.canWrite)) {
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
    // Редактор берётся у приёмника, а не у источника: операцию выполняет
    // движок, один на все провайдеры, и получить его нужно там, где заведомо
    // умеют принимать. У источника его может не быть вовсе — это не мешает
    // копировать из него.
    final editor = _destinationPanel.editor;
    final targets = this.targets;
    if (editor == null || targets.isEmpty || isBusy) {
      return;
    }

    final resolved = await _resolveDestination();
    final destination = resolved.node! as DirectoryNode;
    final followLinks = param<bool>(followLinksParam) ?? false;
    final operation =
        moves
            ? editor.move(targets, destination, followLinks: followLinks)
            : editor.copy(targets, destination, followLinks: followLinks);

    // Аренда источника — на всё время работы, а не на каждое чтение: между
    // чтениями панель успевает уйти, а работа, отправленная в фон, продолжает
    // читать оттуда, откуда она ушла.
    final source = panel.leaseProvider();

    try {
      await runOperation(operation, message: moves ? 'Moving…' : 'Copying…');
    } finally {
      // Отпускаются обе — и после отмены, и после ошибки: `finally` для того
      // здесь и стоит.
      await resolved.release();
      await source?.release();
      // Обе панели теперь показывают не то, что на диске: в приёмнике объекты
      // появились, из источника при переносе исчезли.
      panel.selection.clear();
      await panel.reload();
      await _reloadDestination();
    }
  }

  /// Каталог-приёмник по пути из параметра — вместе с арендой.
  ///
  /// Аренда здесь не формальность: приёмник задают строкой, и она может вести
  /// не туда, где панель стоит. Тогда архив по дороге монтируется ради этой
  /// работы, и отпустить его, кроме неё, некому.
  Future<ResolvedNode> _resolveDestination() async {
    final path = param<String>(destinationParam)?.trim() ?? '';
    if (path.isEmpty) {
      throw const FsError('', FsErrorKind.invalidName);
    }

    // Путь разбирает панель-приёмник: он может проходить через несколько
    // провайдеров («…/archive.zip:zip:/inner»), и одному провайдеру такое
    // не по силам.
    final resolved = await _destinationPanel.resolvePath(path).result;
    var node = resolved.node;
    if (node is LinkNode) {
      // Ссылка на каталог — тоже каталог: копировать «в неё» можно.
      node = await node.provider.resolveLink(node).result;
    }
    if (node == null) {
      await resolved.release();
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node is! DirectoryNode) {
      await resolved.release();
      throw FsError(path, FsErrorKind.notADirectory);
    }
    return ResolvedNode(node, resolved.lease);
  }

  /// Панель, в которую идёт работа: пассивная. Ею же задан путь по умолчанию.
  Panel get _destinationPanel => context.target;

  String? get _defaultDestination {
    final directory = _destinationPanel.directory;
    // Полный путь: приёмник может оказаться внутри архива, и часть про
    // локальную ФС из строки выкидывать нельзя.
    return directory?.pathString;
  }

  Future<void> _reloadDestination() async {
    final panel = _destinationPanel;
    // Панель могла за это время уйти в другой каталог — перечитывать имеет смысл
    // только то, куда действительно копировали.
    if (panel.directory != null) {
      await panel.reload();
    }
  }

  // --- окно ---

  /// Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
  /// длительных работ, их берёт на себя [AsyncCommandDialog]. Команде остаётся
  /// то, что у неё своё: куда копировать.
  @override
  DialogSpec? dialogSpec(BuildContext context) =>
      DialogSpec(title: dialogTitle, takesFocus: true, content: AsyncCommandDialog(command: this, form: _form));

  Widget _form(BuildContext context) {
    return CommandDialogForm(
      error: error,
      onCancel: dismiss,
      onSubmit: submit,
      submitLabel: label,
      // Поля те же, что в референсе: откуда и куда. Зазор между строками
      // ставит сама форма.
      children: [
        CommandDialogField(label: 'From', child: FcTextField(controller: _source, enabled: false)),
        CommandDialogField(
          label: 'To',
          child: FcTextField(
            controller: _destination,
            autofocus: true,
            hintText: 'Destination path',
            // Путь задаётся по мере ввода, а не при подтверждении: Enter
            // обрабатывает ядро, и к моменту execute параметр уже должен
            // быть на месте.
            onChanged: (value) => setParam(destinationParam, value),
            onSubmitted: (_) => submit(),
          ),
        ),
        // Значение живёт в параметрах команды, а не в состоянии виджета:
        // окно строит сама команда, и перерисовывает его её же уведомление.
        FcCheckbox(
          label: 'Follow symlinks',
          value: param<bool>(followLinksParam) ?? false,
          onChanged: (value) {
            setParam(followLinksParam, value);
            notifyListeners();
          },
        ),
      ],
    );
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  @override
  String get dialogTitle {
    final targets = this.targets;
    final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
    return '$label $what';
  }

  /// Каталог, из которого идёт работа: показывается в окне.
  String get _sourcePath {
    final panel = context.panel;
    final directory = panel.directory;
    return directory?.displayPath ?? '';
  }

  @override
  void dispose() {
    _destination.dispose();
    _source.dispose();
    super.dispose();
  }
}
