import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_screen.dart';
import 'editor_settings.dart';
import 'text_file.dart';

/// Открыть файл под курсором на правку.
///
/// Идентификатор — тот же, что у заглушки оболочки (`file.edit`): реестр держит
/// прототипы по идентификатору, и модуль занимает её место вместе с `F4`.
class EditFileCommand extends AppCommand {
  EditFileCommand({required this.settings, required this.onSettingsChanged});

  static const String commandId = 'file.edit';

  final EditorSettings settings;
  final void Function() onSettingsChanged;

  @override
  String get id => commandId;

  @override
  String get label => 'Edit';

  @override
  Set<String> get keywords => const {'editor', 'modify', 'change file'};

  @override
  String get description => 'Open the file under the cursor for editing';

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    // Править можно то, что умеют и отдать, и принять: у результатов поиска
    // байтов нет вовсе, а архив, открытый через временную копию, принять их
    // не может — изменения уехали бы вместе с копией.
    return node != null &&
        // Занятая панель второго чтения не начинает: она уже читает — либо
        // каталог, либо файл, — и говорить об этом ей нечем дважды.
        !context.panel.busy &&
        node is! DirectoryNode &&
        node is! ParentDirNode &&
        node.provider is FileContentProvider &&
        node.provider is FileContentReceiver;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final node = context.node;
    if (node == null) {
      return;
    }

    final source = node.provider;
    if (source is! FileContentProvider || node.provider is! FileContentReceiver) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    if (node.size > settings.maxFileSize) {
      context.app.toasts.show(
        'File is too large: ${formatBytesLong(node.size)}, limit is ${formatSize(settings.maxFileSize)}',
      );
      return;
    }

    // Открытие ведёт панель — цепочкой, одной занятостью на всё: спросить
    // права, при отказе спросить человека, прочитать. Одна работа значит и одну
    // цель для `Esc`: между шагами панель не освобождается ни на миг.
    var readOnly = false;
    final TextFile file;
    try {
      file = await context.panel.runWork<TextFile>((op) async {
        // Права спрашиваются **до чтения**: узнать об отказе на `F2`, после
        // часа работы, значит остаться с текстом, который некуда деть — «Save
        // As» у редактора нет. И до чтения же, а не после: незачем тянуть с
        // сервера целый файл, чтобы затем спросить, открывать ли его вообще.
        readOnly = !await _canWrite(op, node);
        if (readOnly && !await _agreesToReadOnly(context, node)) {
          throw const OperationCanceled();
        }

        // Вложенной работой: ход дела она отдаёт наверх сама, а отмена идёт к
        // ней встречно — `Esc` прерывает чтение, а не ждёт его конца.
        return op.delegate(TextFile.reading(source as FileContentProvider), node);
      }, status: 'Opening ${node.name}…');
    } on OperationCanceled {
      // Передумали — это обычный ход дела, а не беда: экран не открывается, и
      // говорить не о чем.
      return;
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.notSupported) {
        // Не текст в UTF-8: правка и сохранение записали бы знаки замены
        // вместо исходных байтов, то есть испортили бы файл молча.
        context.app.toasts.show('Not a UTF-8 text file: ${node.name}');
        return;
      }
      rethrow;
    }

    context.app.view.pushViewportContent(
      ViewportPosition.fullscreen,
      EditorScreen(
        node: node,
        file: file,
        readOnly: readOnly,
        // Правку архива не закончить, если панель из него выйдет: аренда
        // держится до закрытия экрана.
        lease: context.panel.leaseProvider(),
        wordWrap: settings.wordWrap,
        showLineNumbers: settings.showLineNumbers,
        onWrapChanged: (value) {
          settings.wordWrap = value;
          onSettingsChanged();
        },
        onLineNumbersChanged: (value) {
          settings.showLineNumbers = value;
          onSettingsChanged();
        },
      ),
    );
  }

  /// Пустят ли писать. Провайдер, который отвечать не умеет, не обещает
  /// ничего — тогда всё как раньше: узнаем при сохранении.
  ///
  /// Спрашивается это звеном общей цепочки, потому что спрашивать бывает
  /// далеко: по ssh проба — поход на сервер, и сама по себе она была бы вторым
  /// немым замиранием, ради избавления от которого затевался Г9.
  Future<bool> _canWrite(TaskOperation<void, TextFile> op, FsNode node) async {
    final provider = node.provider;
    if (provider is! WriteAccessCheck) {
      return true;
    }
    // Каст, а не продвижение типа: `WriteAccessCheck` наследником
    // `TreeProvider` не является, а Dart сужает тип только до подтипа — ровно
    // поэтому касты стоят и у соседних умений провайдера.
    final check = provider as WriteAccessCheck;

    op.report(message: 'Checking ${node.name}…');
    try {
      return await check.canWriteTo(node);
    } on FsError {
      // Не смогли выяснить — не выдумываем: молчим, как провайдер без проверки
      // вовсе. Отмену не глотаем: её разбирает вызывающий.
      return true;
    }
  }

  /// Спросить, открывать ли то, что нельзя будет записать.
  ///
  /// Открыть — можно: файл показывается, поиск по нему работает, правка
  /// выключена. Молчаливое открытие «как обычно» хуже: час работы упёрся бы в
  /// отказ на `F2`.
  Future<bool> _agreesToReadOnly(CommandContext context, FsNode node) {
    final view = context.app.view;
    final answer = Completer<bool>();
    late final String dialogId;
    void reply(bool value) {
      view.closeDialog(dialogId);
      if (!answer.isCompleted) {
        answer.complete(value);
      }
    }

    dialogId = view.showDialog(
      DialogSpec(
        title: 'Read-only file',
        content: CommandDialogConfirm(
          message: '${node.displayPath} cannot be written. Open it for reading?',
          confirmLabel: 'Open read-only',
          onCancel: () => reply(false),
          onConfirm: () => reply(true),
        ),
        onSubmit: () => reply(true),
        onDismiss: () => reply(false),
      ),
    );

    return answer.future;
  }
}

/// Записать правки в файл.
class SaveFileCommand extends AppCommand {
  static const String commandId = 'editor.save';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => 'Save';

  @override
  String get description => 'Write the changes back to the file';

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  /// Сохранять нечего, пока ничего не меняли: кнопка приглушена, а не делает
  /// вид, что сработала.
  ///
  /// В файле, открытом только на чтение, сохранять нечего никогда: правки в нём
  /// взяться неоткуда, а обещать запись, которой не будет, — хуже отказа.
  @override
  bool isExecutable(CommandContext context) {
    final screen = _editorOf(context.app);
    return screen != null && screen.modified && !screen.readOnly;
  }

  /// Спрашивает перед записью — единственным необратимым действием редактора.
  ///
  /// Спрашивает **всегда**, на какой бы клавише её ни позвали: `F2` соседствует
  /// с `F3` и `F5`, а `Cmd-S` — нет, но команда одна, и разное поведение у
  /// одной команды запрещено сквозным правилом. К тому же о клавише
  /// [CommandContext] и не знает.
  @override
  Future<void> execute(CommandContext context) async {
    final screen = _editorOf(context.app) ?? _editorOf(_app);
    if (screen == null || !screen.modified || screen.readOnly) {
      return;
    }

    final view = context.app.view;
    final state = _WriteState();
    late final String dialogId;
    void close() {
      view.closeDialog(dialogId);
      state.dispose();
    }

    Future<void> save() async {
      if (state.busy) {
        return;
      }
      state.started();
      try {
        await saveEditor(screen);
      } on FsError catch (error) {
        // Окно остаётся и говорит, почему не вышло. Улететь исключению нельзя:
        // ошибка команды уходит в журнал, а из колбэка окна — и вовсе мимо
        // всего, в отчёт о падении.
        state.failed(error.message);
        return;
      } on Object catch (error) {
        state.failed('$error');
        return;
      }
      close();
      context.app.toasts.show('Saved ${screen.node.name}');
    }

    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        content: ListenableBuilder(
          listenable: state,
          builder:
              (context, _) => CommandDialogConfirm(
                // Полный путь, а не одно имя: соглашаются на конкретный файл,
                // и в системном каталоге это важнее всего.
                message: 'Save changes to ${screen.node.displayPath}?',
                confirmLabel: 'Save',
                onCancel: close,
                onConfirm: () => unawaited(save()),
                error: state.error,
                busy: state.busy,
              ),
        ),
        onSubmit: () => unawaited(save()),
        onDismiss: close,
      ),
    );
  }

  String get dialogTitle => 'Save changes';
}

/// Записывает содержимое экрана в файл.
///
/// Через временный файл и переименование там, где источник — настоящая
/// файловая система: `openWrite` обрезает файл сразу, и обрыв на середине
/// оставил бы половину вместо целого. Там, где переименования нет (архив
/// пересобирается целиком, сервер пишет потоком), запись идёт напрямую — там
/// целостность обеспечивает сам источник.
Future<void> saveEditor(EditorScreen screen) async {
  final node = screen.node;
  final parent = node.parentDirectory;
  final provider = node.provider;

  if (parent == null || provider is! FileContentReceiver) {
    throw FsError(node.pathString, FsErrorKind.notSupported);
  }

  final bytes = utf8.encode(screen.textToSave);
  final atomic = provider.capabilities.realFileSystem && provider is NodeEditor;

  if (!atomic) {
    await _write(provider as FileContentReceiver, parent, node.name, bytes);
    screen.markSaved();
    return;
  }

  // Имя со скрывающей точкой: временный файл не должен мозолить глаза в
  // панели, если сохранение всё же оборвётся.
  final temporary = '.${node.name}.fc-save';
  final editor = provider as NodeEditor;

  await _write(provider as FileContentReceiver, parent, temporary, bytes);
  try {
    final written = await editor.lookup(parent, temporary);
    if (written == null) {
      throw FsError(node.pathString, FsErrorKind.io);
    }
    if (!await editor.renameEntry(written, parent, node.name)) {
      throw FsError(node.pathString, FsErrorKind.io);
    }
  } on Object {
    // Недописанное под своим именем выглядело бы как целый файл.
    final leftover = await editor.lookup(parent, temporary);
    if (leftover != null) {
      await editor.deleteEntry(leftover);
    }
    rethrow;
  }

  screen.markSaved();
}

Future<void> _write(FileContentReceiver receiver, DirectoryNode parent, String name, List<int> bytes) async {
  final sink = await receiver.openWrite(parent, name, length: bytes.length);
  await sink.addStream(Stream<List<int>>.value(bytes));
  await sink.close();
}

/// Переключить перенос строк.
///
/// Не на `F2`, как в просмотрщике: там `F2` свободна, а здесь за ней
/// сохранение — то, ради чего редактор и открывают.
class ToggleEditorWrapCommand extends AppCommand {
  static const String commandId = 'editor.wrap';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => _editorOf(_app)?.wordWrap == true ? 'Unwrap' : 'Wrap';

  /// Название меняется по состоянию, а ищут всегда одним словом.
  @override
  Set<String> get keywords => const {'word wrap', 'line wrap'};

  @override
  String get description => 'Wrap long lines in the editor';

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _editorOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = _editorOf(context.app);
    if (screen == null) {
      return;
    }

    screen.toggleWordWrap();
    // Переключилось и закончилось — о таком говорят всплывающим сообщением.
    context.app.toasts.show('Wrap: ${screen.wordWrap ? 'On' : 'Off'}');
  }
}

/// Показать или спрятать номера строк.
class ToggleEditorNumbersCommand extends AppCommand {
  static const String commandId = 'editor.numbers';

  @override
  String get id => commandId;

  /// Подпись постоянная — в отличие от переноса строк, где она меняется:
  /// номера строк видно на самом экране. Что переключилось, говорит
  /// всплывающее сообщение.
  @override
  String get label => 'Line Num';

  @override
  Set<String> get keywords => const {'line numbers', 'gutter'};

  @override
  String get description => 'Show line numbers in the editor';

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _editorOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = _editorOf(context.app);
    if (screen == null) {
      return;
    }

    screen.toggleLineNumbers();
    context.app.toasts.show('Show line numbers: ${screen.showLineNumbers ? 'On' : 'Off'}');
  }
}

/// Закрыть редактор; при несохранённом — спросить.
class CloseEditorCommand extends AppCommand {
  static const String commandId = 'editor.close';

  @override
  String get id => commandId;

  @override
  String get label => 'Quit';

  @override
  Set<String> get keywords => const {'close', 'exit', 'back'};

  @override
  String get description => 'Close the editor';

  EditorScreen? _screenOf(CommandContext context) {
    final screen = context.app.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => context.app.view.contentAt(ViewportPosition.fullscreen) is EditorScreen;

  String get dialogTitle => 'Unsaved changes';

  /// Закрыть — и спросить по дороге, если есть что терять.
  ///
  /// Вопрос задаётся не всегда, и решает это сама команда: снаружи «есть ли у
  /// неё окно» больше никого не касается.
  ///
  /// Ответов три, и основной — «сохранить». `Enter` раньше доставался
  /// `Discard`, то есть самое частое «да, я закончил» стирало работу; теперь он
  /// сохраняет, а потерять правки можно только явно нажав `Discard`.
  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    final screen = _screenOf(context);
    if (screen == null) {
      return;
    }

    void leave() => view.popViewportContent(ViewportPosition.fullscreen);

    if (!screen.modified) {
      leave();
      return;
    }

    final state = _WriteState();
    late final String dialogId;
    void close() {
      view.closeDialog(dialogId);
      state.dispose();
    }

    void discard() {
      close();
      leave();
    }

    Future<void> save() async {
      if (state.busy) {
        return;
      }
      state.started();
      try {
        // То же самое сохранение, что и на `F2`, — и подтверждения оно не
        // просит: согласие уже дано, вопрос был ровно про это.
        await saveEditor(screen);
      } on FsError catch (error) {
        // Не записалось — экран остаётся открытым, а ошибка живёт в этом же
        // окне: уйти, унеся правки, это ровно то, чего просили не делать.
        state.failed(error.message);
        return;
      } on Object catch (error) {
        state.failed('$error');
        return;
      }
      close();
      leave();
    }

    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        content: ListenableBuilder(
          listenable: state,
          builder:
              (context, _) => CommandDialogConfirm(
                message: '${screen.node.name} has unsaved changes.',
                confirmLabel: 'Save',
                alternativeLabel: 'Discard',
                onAlternative: discard,
                onCancel: close,
                onConfirm: () => unawaited(save()),
                error: state.error,
                busy: state.busy,
              ),
        ),
        onSubmit: () => unawaited(save()),
        onDismiss: close,
      ),
    );
  }
}

/// Состояние окна, которое спросило про запись: идёт ли она и чем кончилась.
///
/// Своё состояние окну нужно потому, что запись может не получиться. Пока она
/// идёт, кнопки приглушены; неудача остаётся **в этом же окне**, и экран
/// редактора не закрывается.
///
/// Где ещё её показать, места нет: ошибка команды уходит в журнал
/// (`app_container.dart`), то есть мимо человека. Окно уже открыто и уже про
/// эту самую запись — ему и говорить.
class _WriteState extends ChangeNotifier {
  bool busy = false;
  String? error;

  void started() {
    busy = true;
    error = null;
    notifyListeners();
  }

  void failed(String message) {
    busy = false;
    error = message;
    notifyListeners();
  }
}
