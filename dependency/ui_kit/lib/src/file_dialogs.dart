import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'app_scope.dart';
import 'command_dialog.dart';
import 'directory_tree.dart';
import 'fc_theme.dart';

/// Окно «каталог и имя» и чтение файла по адресу.
///
/// Здесь, а не у того, кто спросил первым: файлом возят и наборы выбора
/// (`docs/spec/settings-presets.md`, §7), и темы оформления
/// (`docs/spec/theme-editor.md`, §10), — а спрашивают об одном и том же.
///
/// Каталог человек выбирает **деревом**, начиная с домашнего: набирать путь
/// руками в файловом менеджере — насмешка, а своего системного диалога у
/// приложения нет и не будет. Ветви перечисляет панель: её провайдер знает и
/// `ssh://`, и нутро архива.

/// Имя файла, предлагаемое по названию вещи.
String safeFileName(String name, {required String fallback}) {
  final safe = name.replaceAll(RegExp(r'[/\\:]'), '-').trim();
  return '${safe.isEmpty ? fallback : safe}.json';
}

/// Прочитать json по адресу — тем же способом, каким читается файл после
/// жеста: разбор адреса ведёт ядро, аренду на время чтения берёт оно же.
///
/// Больше [sizeLimit] — это не настройки, а том данных: указали не на тот файл.
Future<Map<String, dynamic>> readJsonFile(Application app, String path, {int sizeLimit = 4 * 1024 * 1024}) async {
  final content = app.contentAt(FileEntry(name: '', kind: EntryKind.file, path: path, canStream: true));
  final bytes = <int>[];
  await for (final chunk in content.read()) {
    bytes.addAll(chunk);
    if (bytes.length > sizeLimit) {
      throw const FsError('', FsErrorKind.notSupported);
    }
  }

  final stored = jsonDecode(utf8.decode(bytes));
  if (stored is! Map<String, dynamic>) {
    throw const FormatException();
  }
  return stored;
}

/// Домашний каталог — адресом, который разбирает ядро: экранная сторона своего
/// дома не знает, а `~` источник понимает сам.
const String _home = '~';

/// Окно «каталог и имя»: оба поля правятся, оба подставлены.
///
/// [formatError] — что сказать, если файл не прочитался: «это не набор», «это
/// не тема». Знает это тот, кто просил, а не окно.
///
/// [picks] — по какому имени видно **файл**, который тут выбирают; null —
/// файлы не показываются вовсе, и дерево остаётся деревом каталогов. Так
/// разнятся два окна: выгрузка спрашивает место и имя, а загрузка — готовый
/// файл, и набирать его имя руками, когда он виден в том же дереве, незачем.
Future<void> askFile(
  Application app,
  Strings strings, {
  required String title,
  required String submitLabel,
  required String name,
  required String destinationLabel,
  required String formatError,
  required Future<void> Function(String folder, String name) run,
  bool Function(FileEntry entry)? picks,
}) {
  final view = app.view;
  final closed = Completer<void>();
  late final String dialogId;
  void close() {
    view.closeDialog(dialogId);
    if (!closed.isCompleted) {
      closed.complete();
    }
  }

  // Дом, а не каталог панели: выгружают набор обычно «к себе», а панель в
  // этот миг стоит где угодно — хоть в `/etc`.
  final state = _FileState(
    folder: _home,
    name: name,
    strings: strings,
    run: run,
    app: app,
    formatError: formatError,
    picks: picks,
  );
  state.close = close;

  dialogId = view.showDialog(
    DialogSpec(
      title: title,
      takesFocus: true,
      content: _FileForm(state: state, submitLabel: submitLabel, destinationLabel: destinationLabel),
      onSubmit: state.submit,
      onDismiss: close,
    ),
  );
  return closed.future;
}

/// Что набрано в окне файла и чем кончилась попытка.
class _FileState extends ChangeNotifier {
  _FileState({
    required this.folder,
    required this.name,
    required this.strings,
    required this.run,
    required this.app,
    required this.formatError,
    this.picks,
  }) : selected = folder;

  /// Что сказать про файл, который не прочитался.
  final String formatError;

  /// По какому имени видно файл, который тут выбирают; null — выбирают место.
  final bool Function(FileEntry entry)? picks;

  /// Что подсвечено в дереве: ветвь или файл.
  ///
  /// Отдельно от [folder]: выбранный файл лежит **в** каталоге, и подсветить
  /// надо его самого, а не то, что его держит.
  String selected;

  /// Выбрали в дереве — местом или файлом.
  void choose(String path, bool isFile) {
    selected = path;
    if (isFile) {
      final at = path.lastIndexOf('/');
      folder = at > 0 ? path.substring(0, at) : path;
      name = path.substring(at + 1);
    } else {
      folder = path;
    }
    notifyListeners();
  }

  final Application app;

  String folder;
  String name;

  final Strings strings;
  final Future<void> Function(String folder, String name) run;

  bool busy = false;

  late final VoidCallback close;

  /// Отказ говорится **тостом**, а не полем в окне.
  ///
  /// Сообщение внутри формы отъедает у окна место и двигает поля ровно тогда,
  /// когда в них собираются что-то поправить; тост висит поверх и места не
  /// занимает (`docs/widgets.md`, «Всплывающие сообщения»). Окно при этом
  /// остаётся открытым: поправить надо здесь же.
  Future<void> submit() async {
    if (busy) {
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await run(folder.trim(), name.trim());
      close();
    } on FsError catch (failure) {
      app.toasts.fail(failure.message);
    } on FormatException {
      // Испорченный файл — отказ словами, а не пустота молчанием.
      app.toasts.fail(strings.tr(formatError));
    } on Object catch (failure) {
      app.toasts.fail('$failure');
    }
    busy = false;
    notifyListeners();
  }
}

class _FileForm extends StatefulWidget {
  const _FileForm({required this.state, required this.submitLabel, required this.destinationLabel});

  final _FileState state;
  final String submitLabel;

  /// Как назвать выбранное место: «Save to» у выгрузки, «Read from» у
  /// загрузки — дело у окон разное, и подпись о нём говорит своё.
  final String destinationLabel;

  @override
  State<_FileForm> createState() => _FileFormState();
}

class _FileFormState extends State<_FileForm> {
  late final TextEditingController _name = TextEditingController(text: widget.state.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.state.name.lastIndexOf('.').clamp(0, widget.state.name.length),
    );

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_followState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_followState);
    _name.dispose();
    super.dispose();
  }

  /// Выбранное в дереве видно и в поле имени.
  ///
  /// Иначе в нём остаётся прежнее, и окно показывает два разных ответа на один
  /// вопрос — а запишется то, что в поле.
  void _followState() {
    if (_name.text == widget.state.name) {
      return;
    }
    _name.value = TextEditingValue(
      text: widget.state.name,
      selection: TextSelection.collapsed(offset: widget.state.name.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder:
          (context, _) => CommandDialogForm(
            onCancel: state.close,
            onSubmit: state.submit,
            submitLabel: widget.submitLabel,
            busy: state.busy,
            children: [
              // Подпись вровень с первой строкой дерева, а не по его середине:
              // у высокого управления середина уезжает в пустоту.
              CommandDialogField.column(
                label: context.strings.tr(state.picks == null ? 'Folder' : 'File'),
                children: [
                  SizedBox(
                    // Размер задаётся здесь, и оба измерения: окно меряет своё
                    // содержимое (`IntrinsicWidth`), а список прокрутки мерить
                    // себя не умеет — ради того он и ленив.
                    width: FcTheme.of(context).metrics.dialogLabelWidth * 3,
                    height: FcTheme.of(context).metrics.rowHeight * 9,
                    child: _DropArea(
                      state: state,
                      child: FcDirectoryTree(
                        root: _home,
                        rootTitle: context.strings.tr('Home'),
                        children: state.app.activePanel.namesIn,
                        selected: state.selected,
                        shows: state.picks,
                        onSelected: state.choose,
                      ),
                    ),
                  ),
                ],
              ),
              // Выбранное — своим полем, с подписью слева, как у соседей: в
              // дереве видна подсветка строки, а куда именно ляжет файл, из
              // неё не прочесть — одноимённых каталогов в разных местах
              // сколько угодно.
              CommandDialogField(
                label: context.strings.tr(widget.destinationLabel),
                child: Text(
                  state.folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FcTheme.of(context).dialogTextStyle,
                ),
              ),
              CommandDialogField(
                label: context.strings.tr('File name'),
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

/// Дерево, принимающее брошенный снаружи файл.
///
/// Перетащить файл в окно — короче, чем искать его в дереве, и человек к этому
/// привык: в панель уже бросают мышью (`docs/spec/drag-and-drop.md`). Службы
/// может не быть вовсе — тогда область остаётся обычным деревом.
///
/// Бросают **файл или каталог**, и разбирается это тем же способом, что и
/// выбор в дереве: файл даёт место и имя, каталог — только место.
class _DropArea extends StatelessWidget {
  const _DropArea({required this.state, required this.child});

  final _FileState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dnd = state.app.dragAndDrop;
    if (dnd == null) {
      return child;
    }
    final theme = FcTheme.of(context);

    return dnd.target(
      // Хозяин — само окно: бросают в него из панели, а панель себе приёмником
      // не бывает.
      owner: state,
      // Принимается вся область: разбирать, над какой строкой дерева отпустили,
      // незачем — брошенное само говорит, откуда оно.
      spotAt: (_) => const DropSpot(destination: ''),
      onDrop: (_, payload) async => _take(payload),
      builder:
          (context, hovered) => Container(
            foregroundDecoration:
                hovered == null
                    ? null
                    : BoxDecoration(
                      border: Border.all(color: theme.colors.markedBar, width: theme.metrics.focusRingWidth),
                      borderRadius: BorderRadius.circular(theme.metrics.panelRadius),
                    ),
            child: child,
          ),
    );
  }

  /// Первое брошенное и берём: окно спрашивает **один** файл, и выбирать за
  /// человека, какой из пяти он имел в виду, нечем.
  void _take(DropPayload payload) {
    if (payload.entries.firstOrNull case final entry?) {
      state.choose(entry.path, !entry.canEnter);
      return;
    }
    if (payload.paths.firstOrNull case final path?) {
      // Из системы приезжает путь, а не строка списка: каталог это или файл,
      // видно по тому, как он кончается, — и по имени, которое окно ждёт.
      state.choose(path, !path.endsWith('/'));
    }
  }
}
