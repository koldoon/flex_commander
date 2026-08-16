import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/async/async_operation.dart';
import '../../model/async/operation_request.dart';
import '../../model/tree/fs_node.dart';
import '../../model/tree/tree_provider.dart';
import '../../view/dialogs/command_dialog.dart';
import 'app_command.dart';

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
            child: TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Directory name', isDense: true),
              // Имя задаётся по мере ввода, а не при подтверждении: Enter
              // обрабатывает ядро, и к моменту execute параметр уже должен быть
              // на месте.
              onChanged: (value) => setParam(nameParam, value),
              onSubmitted: (_) => submit(),
            ),
          ),
    );
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
abstract class RemoveCommandBase extends AppCommand implements AsyncCommand {
  /// Куда девается объект: в корзину или совсем.
  bool get toTrash;

  AsyncOperation<void>? _operation;
  StreamSubscription<OperationRequest>? _requests;
  StreamSubscription<OperationProgress>? _progress;

  bool _running = false;
  double? _progressValue;
  String _message = '';

  /// Вопрос, на который сейчас ждут ответа: «объект не удалился, что делать?».
  OperationRequest? _question;

  @override
  bool get hasDialog => true;

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
    if (editor == null || targets.isEmpty || _running) {
      return;
    }

    _running = true;
    _message = 'Deleting…';
    notifyListeners();

    final operation = editor.remove(targets, toTrash: toTrash);
    _operation = operation;

    // Подписки ставятся сразу: операция начинает работу следующим шагом цикла
    // событий и до тех пор ничего не теряется.
    _progress = operation.progress.listen((event) {
      _progressValue = event.percent;
      _message = event.message;
      notifyListeners();
    });
    _requests = operation.requests.listen((request) {
      if (!hasOpenDialog) {
        // Спросить некого — например, команду запустил сценарий.
        request.respond(request.defaultOption);
        return;
      }
      _question = request;
      notifyListeners();
    });

    try {
      await operation.result;
    } on OperationCanceled {
      // Прервано пользователем: удалённое останется удалённым.
    } finally {
      unawaited(_progress?.cancel());
      unawaited(_requests?.cancel());
      _running = false;
      _question = null;

      // Часть объектов могла исчезнуть, часть остаться: список в панели больше
      // не совпадает с диском.
      panel.selection.clear();
      await panel.reload();
      notifyListeners();
    }
  }

  // --- AsyncCommand ---

  @override
  double? get progress => _progressValue;

  @override
  String get progressMessage => _message;

  @override
  bool get isRunning => _running;

  @override
  Future<void> get completion => _completion.future;
  final Completer<void> _completion = Completer<void>();

  @override
  void cancel() {
    _operation?.cancel();
    if (!_running) {
      closeDialog();
    }
  }

  /// Ответ на вопрос, заданный по ходу работы.
  void answer(OperationOption option) {
    _question?.respond(option);
    _question = null;
    notifyListeners();
  }

  // --- окно ---

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) {
        final question = _question;
        if (question != null) {
          return CommandDialogQuestion(message: question.message, options: question.options, onAnswer: answer);
        }
        if (_running) {
          return CommandDialogProgress(progress: _progressValue, message: _message, onCancel: cancel);
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

  String get _confirmationMessage {
    final targets = this.targets;
    final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
    return toTrash ? 'Move $what to Trash?' : 'Delete $what permanently? This cannot be undone.';
  }

  @override
  Future<void> submit() async {
    await super.submit();
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}
