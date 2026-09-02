import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'navigation_settings.dart';

/// Пометка по маске: `+` помечает, `-` снимает.
///
/// Две команды, а не одна с параметром: в списке команд и в справке они должны
/// читаться порознь (`spec/file-masks.md`, §3).
abstract class MaskSelectionCommandBase extends AppCommand {
  MaskSelectionCommandBase({required this.settings, required this.save});

  /// Маска: задают параметром — идёт мимо окна.
  static const String maskParam = 'mask';

  final NavigationSettings Function() settings;
  final void Function() save;

  /// Добавляет совпавшее к пометке или убирает из неё.
  bool get marks;

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;

    void apply(String patterns) {
      final mask = FileMask.parse(patterns);
      if (mask.isEmpty) {
        return;
      }
      // «..» не помечается никакой маской: это не объект, а способ выйти
      // наверх.
      final matched = {
        for (final entry in panel.entries)
          if (!entry.isParent && mask.matches(entry.name)) entry.name,
      };
      // Одной просьбой на всю маску: до ядра пометка едет именами, и слать по
      // сообщению на файл значило бы гнать их сотнями.
      if (marks) {
        // Пометка **дополняется**, а не заменяется: `+` дважды с разными
        // масками помечает и то, и другое. Так же ведёт себя mc.
        panel.setMarks({...panel.marked, ...matched});
      } else {
        panel.setMarks({...panel.marked}..removeAll(matched));
      }
      settings().rememberMask(patterns.trim());
      save();
    }

    final given = context.invocation.param<String>(maskParam);
    if (given != null) {
      apply(given);
      return;
    }

    final view = context.app.view;
    final state = MaskDialogState(
      recent: List.of(settings().recentMasks),
      // Считает совпадения, пока набирают: единственное место, где маска
      // молчала бы до самого `Enter`, а ошибиться в ней легко.
      count: (patterns) {
        final mask = FileMask.parse(patterns);
        if (mask.isEmpty) {
          return 0;
        }
        return panel.entries.where((entry) => !entry.isParent && mask.matches(entry.name)).length;
      },
      total: panel.entries.where((entry) => !entry.isParent).length,
      apply: apply,
    );

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: label,
        takesFocus: true,
        content: MaskDialogForm(state: state, submitLabel: marks ? 'Mark' : 'Unmark'),
        onSubmit: state.submit,
        onDismiss: state.close,
      ),
    );
  }
}

/// Пометить по маске.
class SelectByMaskCommand extends MaskSelectionCommandBase {
  SelectByMaskCommand({required super.settings, required super.save});

  static const String commandId = 'panel.selection.selectByMask';

  @override
  String get id => commandId;

  @override
  String get label => 'Select by mask';

  @override
  String get description => 'Mark everything matching a mask like «*.dart;*.md»';

  @override
  Set<String> get keywords => const {'mark', 'wildcard', 'pattern', 'select files'};

  @override
  bool get marks => true;
}

/// Снять пометку по маске.
class DeselectByMaskCommand extends MaskSelectionCommandBase {
  DeselectByMaskCommand({required super.settings, required super.save});

  static const String commandId = 'panel.selection.deselectByMask';

  @override
  String get id => commandId;

  @override
  String get label => 'Deselect by mask';

  @override
  String get description => 'Unmark everything matching a mask like «*.dart;*.md»';

  @override
  Set<String> get keywords => const {'unmark', 'wildcard', 'pattern'};

  @override
  bool get marks => false;

  @override
  bool isExecutable(CommandContext context) => super.isExecutable(context) && context.panel.marked.isNotEmpty;
}

/// Что набрано в окне маски и что из этого выйдет.
class MaskDialogState extends ChangeNotifier {
  MaskDialogState({required this.recent, required this.count, required this.total, required this.apply});

  /// Недавние маски, свежие впереди.
  final List<String> recent;

  /// Сколько объектов совпадёт с набранным.
  final int Function(String patterns) count;

  /// Сколько объектов в каталоге всего — без «..».
  final int total;

  final void Function(String patterns) apply;

  String mask = '';
  VoidCallback? close;

  /// Набрана ли маска: пока нет, счётчику нечего считать.
  bool get typing => mask.trim().isNotEmpty;

  /// Что показать под полем: «12 of 40», а пока маска не набрана — «No files
  /// selected».
  ///
  /// Пустая строка на этом месте оставляла бы дыру между полем и недавними
  /// масками, и человек искал бы в ней смысл. Приглушённо — потому что это
  /// ещё не ответ, а его отсутствие.
  String get matched => typing ? '${count(mask)} of $total' : 'No files selected';

  void typed(String value) {
    mask = value;
    notifyListeners();
  }

  void submit() {
    if (mask.trim().isEmpty) {
      close?.call();
      return;
    }
    apply(mask);
    close?.call();
  }
}

/// Поле маски, недавние маски под ним и счётчик совпавшего.
class MaskDialogForm extends StatefulWidget {
  const MaskDialogForm({required this.state, required this.submitLabel, super.key});

  final MaskDialogState state;
  final String submitLabel;

  @override
  State<MaskDialogForm> createState() => _MaskDialogFormState();
}

class _MaskDialogFormState extends State<MaskDialogForm> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'mask');
  int _selected = -1;

  /// Размер страницы для `PgUp`/`PgDn`: список меряет обзор и кладёт его сюда.
  final FcPickPage _page = FcPickPage();

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<FcPickRow> get _found =>
      FcPickList.filter([for (final mask in widget.state.recent) FcPickRow(id: mask, title: mask)], _field.text);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final found = _found;
    final moved = FcPickList.moveSelection(event, selected: _selected, count: found.length, wrap: false, page: _page);
    if (moved == null) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _selected = moved;
      if (moved >= 0) {
        _write(found[moved].id);
      }
    });
    return KeyEventResult.handled;
  }

  void _write(String value) {
    _field.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    widget.state.typed(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final found = _found;
        return CommandDialogForm(
          onCancel: state.close ?? () {},
          onSubmit: state.submit,
          submitLabel: widget.submitLabel,
          children: [
            CommandDialogField(
              label: 'Mask',
              child: Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                child: FcTextField(
                  controller: _field,
                  autofocus: true,
                  hintText: '*.dart;*.md',
                  onChanged: state.typed,
                  onSubmitted: (_) => state.submit(),
                ),
              ),
            ),
            // Сколько совпало — видно до нажатия, а не после.
            CommandDialogField.wide(
              child: Text(
                state.matched,
                style:
                    state.typing
                        ? theme.dialogLabelStyle
                        : theme.dialogLabelStyle.copyWith(color: theme.colors.inputHint),
              ),
            ),
            if (found.isNotEmpty)
              CommandDialogField.wide(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: (theme.metrics.rowHeight + theme.metrics.rowGap) * 6),
                  child: FcPickList(
                    rows: found,
                    query: _field.text,
                    selected: _selected,
                    page: _page,
                    onTap: (mask) {
                      setState(() => _write(mask));
                      state.submit();
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
