import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_saving.dart';
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
    final entry = context.entry;
    final source = context.panel.source;
    // Править можно то, что умеют и отдать, и принять: у результатов поиска
    // байтов нет вовсе, а архив, открытый через временную копию, принять их
    // не может — изменения уехали бы вместе с копией.
    return entry != null &&
        // Занятая панель второго чтения не начинает: она уже читает — либо
        // каталог, либо файл, — и говорить об этом ей нечем дважды.
        !context.panel.busy &&
        !entry.isDirectory &&
        !entry.isParent &&
        source.canStream &&
        source.canReceive;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final entry = context.entry;
    final panel = context.panel;
    if (entry == null) {
      return;
    }

    if (!panel.source.canStream || !panel.source.canReceive) {
      throw FsError(entry.path, FsErrorKind.notSupported);
    }

    if (entry.size > settings.maxFileSize) {
      context.app.toasts.show(
        'File is too large: ${formatBytesLong(entry.size)}, limit is ${formatSize(settings.maxFileSize)}',
      );
      return;
    }

    final bytes = panel.contentOf(entry);

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
        if (!await _canWrite(op, panel, entry)) {
          switch (await _askReadOnly(context, entry)) {
            case _ReadOnlyChoice.cancel:
              throw const OperationCanceled();
            case _ReadOnlyChoice.readOnly:
              readOnly = true;
            case _ReadOnlyChoice.elevate:
              // Правим как обычно: о том, что записать не дадут, узнает сама
              // запись — и предложит повышение.
              readOnly = false;
          }
        }

        // Вложенной работой: ход дела она отдаёт наверх сама, а отмена идёт к
        // ней встречно — `Esc` прерывает чтение, а не ждёт его конца.
        return op.delegate(TextFile.reading(bytes), entry);
      }, status: 'Opening ${entry.name}…');
    } on OperationCanceled {
      // Передумали — это обычный ход дела, а не беда: экран не открывается, и
      // говорить не о чем.
      return;
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.notSupported) {
        // Не текст в UTF-8: правка и сохранение записали бы знаки замены
        // вместо исходных байтов, то есть испортили бы файл молча.
        context.app.toasts.show('Not a UTF-8 text file: ${entry.name}');
        return;
      }
      rethrow;
    }

    context.app.view.pushViewportContent(
      ViewportPosition.fullscreen,
      EditorScreen(
        entry: entry,
        file: file,
        readOnly: readOnly,
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
  Future<bool> _canWrite(TaskOperation<void, TextFile> op, Panel panel, FileEntry entry) async {
    op.report(message: 'Checking ${entry.name}…');
    try {
      // Спрашивает ядро: права знает та сторона, где лежит файл.
      return await panel.canWriteTo(entry);
    } on FsError {
      // Не смогли выяснить — не выдумываем: молчим, как источник без проверки
      // вовсе. Отмену не глотаем: её разбирает вызывающий.
      return true;
    }
  }

  /// Спросить, что делать с файлом, в который писать не дают.
  ///
  /// Открыть — можно: файл показывается, поиск по нему работает, правка
  /// выключена. Молчаливое открытие «как обычно» хуже: час работы упёрся бы в
  /// отказ на `F2`.
  ///
  /// Третий ответ — «править всё равно» — появляется только там, где повышать
  /// есть чем. Пароля он не просит: спросит его сохранение, когда до него
  /// дойдёт.
  ///
  /// `Enter` при этом остаётся на «только чтение»: соглашаться вслепую на путь,
  /// который потом спросит пароль администратора, человек не должен.
  Future<_ReadOnlyChoice> _askReadOnly(CommandContext context, FileEntry entry) {
    final view = context.app.view;
    final answer = Completer<_ReadOnlyChoice>();
    late final String dialogId;
    void reply(_ReadOnlyChoice value) {
      view.closeDialog(dialogId);
      if (!answer.isCompleted) {
        answer.complete(value);
      }
    }

    final elevation = context.app.elevation;
    final mayElevate = elevation.enabled && context.panel.source.isShellHost;

    dialogId = view.showDialog(
      DialogSpec(
        title: 'Read-only file',
        content: CommandDialogConfirm(
          message:
              mayElevate
                  ? '${entry.path} cannot be written.\n'
                      'Open it for reading, or edit it anyway and save as administrator?'
                  : '${entry.path} cannot be written. Open it for reading?',
          confirmLabel: 'Open read-only',
          alternativeLabel: mayElevate ? 'Edit anyway' : null,
          onAlternative: mayElevate ? () => reply(_ReadOnlyChoice.elevate) : null,
          onCancel: () => reply(_ReadOnlyChoice.cancel),
          onConfirm: () => reply(_ReadOnlyChoice.readOnly),
        ),
        onSubmit: () => reply(_ReadOnlyChoice.readOnly),
        onDismiss: () => reply(_ReadOnlyChoice.cancel),
      ),
    );

    return answer.future;
  }
}

/// Что человек выбрал, узнав, что писать в файл не дают.
enum _ReadOnlyChoice {
  /// Передумал открывать вовсе.
  cancel,

  /// Открыть на чтение: показать и дать поискать, правку выключить.
  readOnly,

  /// Править всё равно — а записать потом от администратора.
  elevate,
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
        await context.app.runOperation().run(
          OperationSpec(
            kind: EditorSaving.kind,
            targets: Targets.paths([screen.entry.path]),
            options: {EditorSaving.textOption: screen.textToSave},
          ),
        );
        screen.markSaved();
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
      context.app.toasts.show('Saved ${screen.entry.name}');
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
                message: 'Save changes to ${screen.entry.path}?',
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
        await context.app.runOperation().run(
          OperationSpec(
            kind: EditorSaving.kind,
            targets: Targets.paths([screen.entry.path]),
            options: {EditorSaving.textOption: screen.textToSave},
          ),
        );
        screen.markSaved();
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
                message: '${screen.entry.name} has unsaved changes.',
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
