import 'package:flutter/material.dart';

import '../../model/app/panel.dart';
import '../../model/tree/fs_node.dart';
import '../../model/tree/tree_provider.dart';
import '../../view/dialogs/command_dialog.dart';
import '../../view/theme/app_theme.dart';
import 'app_command.dart';
import 'async_command_base.dart';

/// Копирование выбранных объектов в другой каталог.
class CopyCommand extends TransferCommandBase {
  @override
  String get id => 'file.copy';

  @override
  String get label => 'Copy';

  @override
  bool get moves => false;
}

/// Перенос выбранных объектов в другой каталог.
///
/// Отдельная команда, а не параметр [CopyCommand]: у неё своя клавиша, своя
/// кнопка и своя строка в списке команд.
class MoveCommand extends TransferCommandBase {
  @override
  String get id => 'file.move';

  @override
  String get label => 'Move';

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
  }

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

    final provider = _destinationPanel.provider;
    var node = await provider.resolvePath(path).result;
    if (node is LinkNode) {
      // Ссылка на каталог — тоже каталог: копировать «в неё» можно.
      node = await provider.resolveLink(node).result;
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
    return directory == null ? null : _destinationPanel.provider.pathOf(directory);
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

        return CommandDialogForm(
          error: error,
          onCancel: dismiss,
          onSubmit: submit,
          submitLabel: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(prompt, style: FcTheme.of(context).rowStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              TextField(
                controller: _destination,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Destination path', isDense: true),
                // Путь задаётся по мере ввода, а не при подтверждении: Enter
                // обрабатывает ядро, и к моменту execute параметр уже должен
                // быть на месте.
                onChanged: (value) => setParam(destinationParam, value),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Что и куда — строкой над полем ввода.
  @visibleForTesting
  String get prompt {
    final targets = this.targets;
    final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
    return '$label $what to:';
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }
}
