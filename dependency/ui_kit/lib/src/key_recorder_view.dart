import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'command_dialog.dart';
import 'fc_theme.dart';

/// Окошко правки одной привязки: что за команда, где действует, чем вызывается
/// сейчас — и четыре кнопки (`docs/spec/key-bindings.md`, §9).
///
/// Правка живёт здесь, а не в списке, по одной причине: в списке набирают
/// запрос, и `Bsp` там обязан стирать букву, а не снимать клавишу. Действие,
/// которое нельзя отменить, не вешают на клавишу правки текста.
class FcKeyRecorder extends StatefulWidget {
  const FcKeyRecorder({
    super.key,
    required this.command,
    required this.context,
    required this.read,
    required this.defaultKeys,
    required this.occupiedBy,
    required this.onAssign,
    required this.onClear,
    required this.onReset,
    required this.onClose,
  });

  /// Что команда делает — строкой, которую человек узнаёт.
  final String command;

  /// Название раздела: где эта клавиша действует.
  final String context;

  /// Чем команду вызывают сейчас; пусто — ничем.
  ///
  /// Замыканием: правка идёт тут же, и записанное строкой осталось бы прежним.
  final String Function() read;

  /// Чем её вызывают по умолчанию; пусто — модуль клавиши не давал.
  final String defaultKeys;

  /// Кто держит эту комбинацию **в том же контексте**; null — никто, и спорить
  /// не о чем (`docs/spec/key-bindings.md`, §4).
  final String? Function(String keys) occupiedBy;

  final void Function(String keys) onAssign;
  final VoidCallback onClear;
  final VoidCallback onReset;
  final VoidCallback onClose;

  @override
  State<FcKeyRecorder> createState() => _FcKeyRecorderState();
}

class _FcKeyRecorderState extends State<FcKeyRecorder> {
  /// Клавиши самого окошка — **разобранные**, а не строками: `Cmd` вне macOS
  /// сворачивается в `Ctrl`, и сравнение с написанным там не совпало бы.
  static final KeyCombination _escape = KeyCombination.parse('Esc');
  static final KeyCombination _enter = KeyCombination.parse('Enter');

  /// Клавиши окошко ловит **своим узлом фокуса**, а не чужими.
  ///
  /// Кнопка, которой начали запись, фокус отдаёт, и нажатие ушло бы мимо — до
  /// рамы, где `Esc` закрывает окно, а `Enter` его подтверждает. Поэтому на
  /// время ожидания фокус берётся сюда.
  late final FocusNode _node = FocusNode(debugLabel: 'key-recorder');

  /// Ждём ли нажатия.
  bool _capturing = false;

  /// О чём спрашиваем: какую клавишу назначаем и у кого отнимаем.
  ({String keys, String holder})? _conflict;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _record() {
    setState(() => _capturing = true);
    _node.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final conflict = _conflict;
    if (conflict != null) {
      return _answer(event, conflict);
    }
    if (!_capturing) {
      // Не ждём — клавиши окошка достаются раме: `Esc` закрывает, `Enter`
      // подтверждает.
      return KeyEventResult.ignored;
    }
    return _capture(event);
  }

  /// Захват: следующее сочетание и становится клавишей.
  KeyEventResult _capture(KeyEvent event) {
    final keys = KeyCombination.fromEvent(event);
    // Одни модификаторы сочетанием не бывают: пока нажат только `Cmd`, ждём
    // дальше.
    if (keys == null) {
      return KeyEventResult.handled;
    }
    if (keys == _escape) {
      setState(() => _capturing = false);
      return KeyEventResult.handled;
    }

    final holder = widget.occupiedBy(keys.toString());
    setState(() {
      _capturing = false;
      _conflict = holder == null ? null : (keys: keys.toString(), holder: holder);
    });
    if (holder == null) {
      widget.onAssign(keys.toString());
    }
    return KeyEventResult.handled;
  }

  /// Ответ на вопрос о споре: отнять или оставить.
  KeyEventResult _answer(KeyEvent event, ({String keys, String holder}) conflict) {
    final keys = KeyCombination.fromEvent(event);
    if (keys == _enter) {
      _take(conflict);
      return KeyEventResult.handled;
    }
    if (keys == _escape) {
      setState(() => _conflict = null);
      return KeyEventResult.handled;
    }
    // Пока вопрос не решён, окошко занято им: чужие нажатия сюда не проходят.
    return KeyEventResult.handled;
  }

  void _take(({String keys, String holder}) conflict) {
    setState(() => _conflict = null);
    widget.onAssign(conflict.keys);
  }

  /// Строка о том, что делаем сейчас.
  ///
  /// Место под неё отведено всегда: строка, то появляющаяся, то пропадающая,
  /// дёргала бы кнопки под руками.
  String get _hint {
    if (_conflict case final conflict?) {
      return context.strings.tr(
        '{keys} belongs to «{command}»',
        args: {'keys': conflict.keys, 'command': conflict.holder},
      );
    }
    if (_capturing) {
      return context.strings.tr('Press the combination; Esc — cancel');
    }
    if (widget.defaultKeys.isEmpty) {
      return context.strings.tr('This command has no key of its own');
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final strings = context.strings;
    final keys = widget.read();
    final conflict = _conflict;
    final alarmed = conflict != null;

    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      child: CommandDialogBody(
        actions:
            conflict != null
                // Спор решается тем же рядом кнопок: второго окна поверх
                // второго окна не будет.
                ? [
                  FcButton(label: strings.tr('Leave it'), onPressed: () => setState(() => _conflict = null)),
                  FcButton(label: strings.tr('Take the key'), onPressed: () => _take(conflict), primary: true),
                ]
                : [
                  // Живой и во время ожидания: приглушённая кнопка отдала бы
                  // фокус, и нажатие ушло бы мимо окошка.
                  FcButton(label: strings.tr('Record'), onPressed: _record),
                  FcButton(label: strings.tr('Clear'), onPressed: keys.isEmpty ? null : widget.onClear),
                  FcButton(label: strings.tr('Reset'), onPressed: keys == widget.defaultKeys ? null : widget.onReset),
                  FcButton(label: strings.tr('Close'), onPressed: widget.onClose, primary: true),
                ],
        children: [
          CommandDialogField(label: strings.tr('Command'), child: Text(widget.command, style: theme.dialogTextStyle)),
          CommandDialogField(
            label: strings.tr('Where it works'),
            child: Text(strings.tr(widget.context), style: theme.dialogTextStyle),
          ),
          CommandDialogField(
            label: strings.tr('Current key'),
            child: Text(
              _capturing ? '…' : (keys.isEmpty ? '—' : keys),
              style: theme.dialogTextStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          CommandDialogField(
            label: strings.tr('Default key'),
            child: Text(widget.defaultKeys.isEmpty ? '—' : widget.defaultKeys, style: theme.dialogTextStyle),
          ),
          // Строка о происходящем — своим `Text`: она служебная и набрана
          // приглушённо, а вопрос о споре цветом отказа.
          CommandDialogField.wide(
            child: Text(
              _hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.statusStyle.copyWith(color: alarmed ? theme.colors.error : theme.colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
