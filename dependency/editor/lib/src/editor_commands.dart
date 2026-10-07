import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_work.dart';
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
  String get label => tr('Edit');

  @override
  Set<String> get keywords => const {'editor', 'modify', 'change file'};

  @override
  String get description => tr('Open the file under the cursor for editing');

  @override
  bool isExecutable(CommandContext context) {
    final entry = context.entry;
    // Править можно то, что умеют и отдать, и принять, — и спрашивают об этом
    // **строку**, а не панель: в находках узлы настоящие и принадлежат своим
    // источникам, а сам список байтов не отдаёт вовсе. Живьём `F4` над
    // находкой поэтому и не работал. Архив, открытый через временную копию,
    // остаётся запретным: у его строк тот же провайдер, что у панели, и
    // принять он не может — изменения уехали бы вместе с копией.
    return entry != null &&
        // Занятая панель второго чтения не начинает: она уже читает — либо
        // каталог, либо файл, — и говорить об этом ей нечем дважды.
        !context.session.busy &&
        !entry.isDirectory &&
        !entry.isParent &&
        entry.canStream &&
        entry.canReceive;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final entry = context.entry;
    final panel = context.session;
    if (entry == null) {
      return;
    }

    if (!entry.canStream || !entry.canReceive) {
      throw FsError(entry.path, FsErrorKind.notSupported);
    }

    if (entry.size > settings.maxFileSize) {
      context.app.toasts.show(
        tr(
          'File is too large: {size}, limit is {limit}',
          args: {'size': formatBytesLong(entry.size), 'limit': formatBytesLong(settings.maxFileSize)},
        ),
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
      file = await context.session.runWork<TextFile>((op) async {
        // Права спрашиваются **до чтения**: узнать об отказе на `F2`, после
        // часа работы, значит остаться с текстом, который некуда деть — «Save
        // As» у редактора нет. И до чтения же, а не после: незачем тянуть с
        // сервера целый файл, чтобы затем спросить, открывать ли его вообще.
        if (!await _canWrite(op, panel, entry)) {
          switch (await _askReadOnly(context, entry)) {
            case _ReadOnlyAnswer.cancel:
              throw const OperationCanceled();
            case _ReadOnlyAnswer.readOnly:
              readOnly = true;
            case _ReadOnlyAnswer.elevate:
              // Правим как обычно: о том, что записать не дадут, узнает сама
              // запись — и предложит повышение.
              readOnly = false;
          }
        }

        // Вложенной работой: ход дела она отдаёт наверх сама, а отмена идёт к
        // ней встречно — `Esc` прерывает чтение, а не ждёт его конца.
        return op.delegate(TextFile.reading(bytes, strings: context.app.strings), entry);
      }, status: tr('Opening {name}…', args: {'name': entry.name}));
    } on OperationCanceled {
      // Передумали — это обычный ход дела, а не беда: экран не открывается, и
      // говорить не о чем.
      return;
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.notSupported) {
        // Строго не читается ни в одной кодировке: правка и сохранение
        // записали бы знаки замены вместо исходных байтов, то есть испортили
        // бы файл молча (`docs/spec/text-encodings.md`, §5).
        context.app.toasts.show(tr('Not a text file: {name}', args: {'name': entry.name}));
        return;
      }
      // Прочее говорится тостом, а не уходит в журнал: человек нажал `F4` и
      // вправе узнать, почему ничего не открылось.
      context.app.toasts.show(error.message);
      return;
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
  Future<bool> _canWrite(TaskOperation<void, TextFile> op, Session panel, FileEntry entry) async {
    op.report(message: tr('Checking {name}…', args: {'name': entry.name}));
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
  Future<_ReadOnlyAnswer> _askReadOnly(CommandContext context, FileEntry entry) {
    final view = context.app.view;
    final answer = Completer<_ReadOnlyAnswer>();
    late final String dialogId;
    void reply(_ReadOnlyAnswer value) {
      view.closeDialog(dialogId);
      if (!answer.isCompleted) {
        answer.complete(value);
      }
    }

    final elevation = context.app.elevation;
    final mayElevate = elevation.enabled && context.session.source.isShellHost;

    dialogId = view.showDialog(
      DialogSpec(
        title: tr('Read-only file'),
        content: CommandDialogConfirm(
          message:
              mayElevate
                  ? tr(
                    '{path} cannot be written.\nOpen it for reading, or edit it anyway and save as administrator?',
                    args: {'path': entry.path},
                  )
                  : tr('{path} cannot be written. Open it for reading?', args: {'path': entry.path}),
          confirmLabel: tr('Open read-only'),
          alternativeLabel: mayElevate ? tr('Edit anyway') : null,
          onAlternative: mayElevate ? () => reply(_ReadOnlyAnswer.elevate) : null,
          onCancel: () => reply(_ReadOnlyAnswer.cancel),
          onConfirm: () => reply(_ReadOnlyAnswer.readOnly),
        ),
        onSubmit: () => reply(_ReadOnlyAnswer.readOnly),
        onDismiss: () => reply(_ReadOnlyAnswer.cancel),
      ),
    );

    return answer.future;
  }
}

/// Что человек выбрал, узнав, что писать в файл не дают.
enum _ReadOnlyAnswer {
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
  String get label => tr('Save');

  @override
  String get description => tr('Write the changes back to the file');

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
      if (state.busy || !_fits(context, screen)) {
        return;
      }
      state.started();
      try {
        await context.app.runOperation().run(
          OperationSpec(
            kind: EditorWork.kind,
            targets: Targets.paths([screen.entry.path]),
            options: _saveOptions(screen),
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
      context.app.toasts.show(tr('Saved {name}', args: {'name': screen.entry.name}));
    }

    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        content: ListenableBuilder(
          listenable: Listenable.merge([state, screen]),
          builder:
              (context, _) => CommandDialogConfirm(
                fields: _encodingFields(context, screen),
                // Полный путь, а не одно имя: соглашаются на конкретный файл,
                // и в системном каталоге это важнее всего.
                message: tr('Save changes to {path}?', args: {'path': screen.entry.path}),
                confirmLabel: tr('Save'),
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

  String get dialogTitle => tr('Save changes');
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
  String get label => _editorOf(_app)?.wordWrap == true ? tr('Unwrap') : tr('Wrap');

  /// Название меняется по состоянию, а ищут всегда одним словом.
  @override
  Set<String> get keywords => const {'word wrap', 'line wrap'};

  @override
  String get description => tr('Wrap long lines in the editor');

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
    context.app.toasts.show(screen.wordWrap ? tr('Wrap: On') : tr('Wrap: Off'));
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
  String get label => tr('Line Num');

  @override
  Set<String> get keywords => const {'line numbers', 'gutter'};

  @override
  String get description => tr('Show line numbers in the editor');

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
    context.app.toasts.show(screen.showLineNumbers ? tr('Show line numbers: On') : tr('Show line numbers: Off'));
  }
}

/// Привести документ в читаемый вид.
///
/// Форматирует не сама: умение приносит модуль форматтера, а команда берёт из
/// реестра первого, кто взялся за этот файл (`docs/spec/formatters.md`, §3).
/// В отличие от показа это **правка**: документ становится изменённым, и
/// возвращает его обычная отмена.
class FormatDocumentCommand extends AppCommand {
  FormatDocumentCommand({required this.maxSize});

  static const String commandId = 'editor.format';

  /// Предел размера — настройкой модуля. Спрашивается при каждом нажатии:
  /// настройку могли только что поменять.
  final int Function() maxSize;

  @override
  String get id => commandId;

  /// Подпись постоянная, в отличие от показа: там `F5` переключает два вида, а
  /// здесь клавиша делает одно дело. Оговорка нужна, чтобы «Format» не
  /// перевелось как формат файла.
  @override
  String get label => tr('Format', context: 'editor');

  @override
  Set<String> get keywords => const {'pretty', 'indent', 'json', 'beautify'};

  @override
  String get description => tr('Format the document');

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.view.contentAt(ViewportPosition.fullscreen);

    return screen is EditorScreen ? screen : null;
  }

  /// Форматтер для правимого файла — первый по приоритету, кто взялся.
  ///
  /// Тип содержимого редактору неизвестен: файл уже прочитан, и определять его
  /// ради ответа «моё ли» никто не станет (`docs/spec/formatters.md`, §2).
  static FormatterSpec? _formatterFor(Application app, EditorScreen screen) {
    for (final spec in app.formatters) {
      if (spec.accepts(screen.entry, null)) {
        return spec;
      }
    }

    return null;
  }

  /// В файле, открытом только на чтение, форматировать нечего: правка в нём не
  /// сохранится, а помеченный несохранённым документ, который нельзя записать, —
  /// обещание того, чего не будет.
  ///
  /// Предел размера здесь **не** спрашивается нарочно: приглушённая подпись не
  /// объясняет, почему, а нажатие обязано ответить. Отказ приходит тостом.
  @override
  bool isExecutable(CommandContext context) {
    final screen = _editorOf(context.app);
    if (screen == null || screen.readOnly) {
      return false;
    }

    return _formatterFor(context.app, screen) != null;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final screen = _editorOf(context.app);
    if (screen == null || screen.readOnly) {
      return;
    }

    final spec = _formatterFor(context.app, screen);
    if (spec == null) {
      return;
    }

    final limit = maxSize();
    if (screen.entry.size > limit) {
      context.app.toasts.show(
        tr(
          'Too large to format: {size}, limit is {limit}',
          args: {'size': formatBytesLong(screen.entry.size), 'limit': formatBytesLong(limit)},
        ),
      );

      return;
    }

    try {
      if (!screen.format(spec.format)) {
        // Нажатие без ответа — ошибка: на экране ничего не поменялось, и без
        // слов непонятно, сработала клавиша или нет.
        context.app.toasts.show(tr('Already formatted'));
      }
    } on FormatException catch (error) {
      // Кривой документ остаётся кривым, а отказ называет место
      // (`docs/spec/formatters.md`, §§5, 6).
      context.app.toasts.show(_refusal(spec.title, error, screen.controller.text));
    }
  }

  /// Отказ называет место: «строка 4, столбец 12» ведёт прямо туда, а смещение
  /// в знаках человеку не говорит ничего.
  String _refusal(String what, FormatException error, String text) {
    final place = placeOfError(error, text);
    final why = error.message;
    if (place == null) {
      return tr('Not valid {what}: {why}', args: {'what': what, 'why': why});
    }

    return tr(
      'Not valid {what}: {why} at line {line}, column {column}',
      args: {'what': what, 'why': why, 'line': place.line, 'column': place.column},
    );
  }
}

/// Закрыть редактор; при несохранённом — спросить.
class CloseEditorCommand extends AppCommand {
  static const String commandId = 'editor.close';

  @override
  String get id => commandId;

  @override
  String get label => tr('Quit');

  @override
  Set<String> get keywords => const {'close', 'exit', 'back'};

  @override
  String get description => tr('Close the editor');

  EditorScreen? _screenOf(CommandContext context) {
    final screen = context.app.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => context.app.view.contentAt(ViewportPosition.fullscreen) is EditorScreen;

  String get dialogTitle => tr('Unsaved changes');

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
      if (state.busy || !_fits(context, screen)) {
        return;
      }
      state.started();
      try {
        // То же самое сохранение, что и на `F2`, — и подтверждения оно не
        // просит: согласие уже дано, вопрос был ровно про это.
        await context.app.runOperation().run(
          OperationSpec(
            kind: EditorWork.kind,
            targets: Targets.paths([screen.entry.path]),
            options: _saveOptions(screen),
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
          listenable: Listenable.merge([state, screen]),
          builder:
              (context, _) => CommandDialogConfirm(
                fields: _encodingFields(context, screen),
                message: tr('{name} has unsaved changes.', args: {'name': screen.entry.name}),
                confirmLabel: tr('Save'),
                alternativeLabel: tr('Discard'),
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

/// Что уходит ядру на запись: текст, кодировка и метка (§5).
Map<String, Object?> _saveOptions(EditorScreen screen) => {
  EditorWork.textOption: screen.textToSave,
  EditorWork.encodingOption: screen.saveAs.name,
  EditorWork.bomOption: screen.bomToSave,
};

/// Поле «в чём сохранять» — только у файла не в юникоде
/// (`docs/spec/text-encodings.md`, §5): исходная кодировка или UTF-8.
List<CommandDialogField> _encodingFields(BuildContext context, EditorScreen screen) {
  if (!screen.asksEncoding) {
    return const [];
  }
  return [
    CommandDialogField(
      label: context.strings.tr('Encoding'),
      child: FcSelect<TextEncoding>(
        options: {screen.encoding: screen.encoding.label, TextEncoding.utf8: TextEncoding.utf8.label},
        value: screen.saveAs,
        onChanged: (encoding) => screen.saveAs = encoding,
      ),
    ),
  ];
}

/// Помещается ли текст в выбранную кодировку. Нет — тост с первым знаком и
/// строкой, запись не идёт, окно остаётся: человек правит текст или выбирает
/// UTF-8 (§5).
bool _fits(CommandContext context, EditorScreen screen) {
  final unsavable = screen.unsavable;
  if (unsavable == null) {
    return true;
  }
  context.app.toasts.show(
    context.app.strings.tr(
      '“{char}” on line {line} does not fit in {encoding}',
      args: {'char': unsavable.char, 'line': '${unsavable.line}', 'encoding': screen.saveAs.label},
    ),
  );
  return false;
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

/// Другая кодировка — окном со списком (`docs/spec/text-encodings.md`, §4).
///
/// Перечитывает **байты файла**, поэтому с несохранёнными правками отказывает:
/// они пропали бы.
class ChooseEditorEncodingCommand extends AppCommand {
  static const String commandId = 'editor.encoding';

  @override
  String get id => commandId;

  @override
  String get label => tr('Encoding');

  @override
  Set<String> get keywords => const {'charset', 'codepage', 'cp1251', 'koi8', 'utf'};

  @override
  String get description => tr('Read the file in another encoding');

  static EditorScreen? _editorOf(Application app) {
    final screen = app.view.contentAt(ViewportPosition.fullscreen);
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
    if (screen.modified) {
      context.app.toasts.show(tr('Save or discard the changes before changing the encoding'));
      return;
    }
    showChoiceDialog<TextEncoding>(
      view: context.app.view,
      title: tr('Encoding'),
      items: TextEncoding.values,
      labelOf: (encoding) => encoding.label,
      current: screen.encoding,
      onChoose: (encoding) {
        if (!screen.reread(encoding)) {
          // В этой кодировке байты не читаются без потерь: править такое
          // значило бы испортить файл. Текст остаётся прежним.
          context.app.toasts.show(tr('The file cannot be read as {encoding}', args: {'encoding': encoding.label}));
        }
      },
    );
  }
}
