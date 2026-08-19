import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';

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

  /// Убирается ли исходный объект.
  bool get moves;

  final TextEditingController _destination = TextEditingController();

  /// Откуда идёт работа. Поле не редактируется — источник задан выбором в
  /// панели, — но остаётся полем: так форма читается как форма.
  final TextEditingController _source = TextEditingController();

  /// Путь набирают сразу: фокус ставит поле ввода.
  @override
  bool get dialogTakesFocus => true;

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
    if (editor == null || targets.isEmpty || isRunning) {
      return;
    }

    final destination = await _resolveDestination();
    final operation = moves ? editor.move(targets, destination) : editor.copy(targets, destination);

    try {
      await runOperation(operation, message: moves ? 'Moving…' : 'Copying…');
    } finally {
      // Обе панели теперь показывают не то, что на диске: в приёмнике объекты
      // появились, из источника при переносе исчезли.
      panel.selection.clear();
      await panel.reload();
      await _reloadDestination();
    }
  }

  /// Каталог-приёмник по пути из параметра.
  Future<DirectoryNode> _resolveDestination() async {
    final path = param<String>(destinationParam)?.trim() ?? '';
    if (path.isEmpty) {
      throw const FsError('', FsErrorKind.invalidName);
    }

    // Путь разбирает панель-приёмник: он может проходить через несколько
    // провайдеров («…/archive.zip:zip:/inner»), и одному провайдеру такое
    // не по силам.
    var node = await _destinationPanel.resolvePath(path).result;
    if (node is LinkNode) {
      // Ссылка на каталог — тоже каталог: копировать «в неё» можно.
      node = await node.provider.resolveLink(node).result;
    }
    if (node == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node is! DirectoryNode) {
      throw FsError(path, FsErrorKind.notADirectory);
    }
    return node;
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

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) {
        final question = this.question;
        if (question != null) {
          return CommandDialogQuestion(request: question, onAnswer: answer, onTextChanged: setAnswerText);
        }
        if (isRunning) {
          return CommandDialogProgress(
            progress: progress,
            message: progressMessage,
            processed: processed,
            total: total,
            totalIsFinal: totalIsFinal,
            bytes: bytes,
            totalBytes: totalBytes,
            bytesPerSecond: bytesPerSecond,
            remaining: remaining,
            itemName: itemName,
            itemProgress: itemProgress,
            itemBytes: itemBytes,
            itemTotalBytes: itemTotalBytes,
            onCancel: cancel,
            // Прятать имеет смысл то, что идёт долго: у не начавшейся работы
            // прятать нечего.
            onBackground: isRunning ? sendToBackground : null,
          );
        }

        final theme = FcTheme.of(context);

        return CommandDialogForm(
          error: error,
          onCancel: dismiss,
          onSubmit: submit,
          submitLabel: label,
          // Поля те же, что в референсе: откуда и куда.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommandDialogField(label: 'From', child: FcTextField(controller: _source, enabled: false)),
              SizedBox(height: theme.metrics.dialogGap),
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
            ],
          ),
        );
      },
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
