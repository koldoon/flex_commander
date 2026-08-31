import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'fc_theme.dart';

/// Подпись поля в окне команды.
///
/// Модулю не нужно знать, каким стилем набирается подпись, — это дело темы,
/// а тема может смениться.
class FcLabel extends StatelessWidget {
  const FcLabel(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: FcTheme.of(context).dialogLabelStyle, textAlign: textAlign);
  }
}

/// Обычный текст окна: значение, пояснение, вопрос.
class FcText extends StatelessWidget {
  const FcText(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: FcTheme.of(context).dialogTextStyle, textAlign: textAlign);
  }
}

/// Флажок с меткой: да или нет.
///
/// Как и кнопка, облегает содержимое: содержимое окна выкладывается
/// растягивающей колонкой, и без этого флажок растянулся бы во всю ширину,
/// а щелчок ловился бы далеко за меткой.
class FcCheckbox extends StatefulWidget {
  const FcCheckbox({
    super.key,
    required this.label,
    this.richLabel,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  final String label;

  /// Подпись разметкой — когда простой строки мало.
  ///
  /// В настройках у неё приглушённая приставка с названием модуля: «*Text
  /// editor:* **Wrap long lines**». Дана — рисуется вместо [label]; сам [label]
  /// при этом обязателен и остаётся: он и подпись по умолчанию, и то, что
  /// прочитает озвучка.
  final InlineSpan? richLabel;
  final bool value;

  /// null — флажок показан, но не меняется.
  final ValueChanged<bool>? onChanged;

  /// Узел фокуса — когда он нужен снаружи.
  final FocusNode? focusNode;

  @override
  State<FcCheckbox> createState() => _FcCheckboxState();
}

class _FcCheckboxState extends State<FcCheckbox> {
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  /// `Space` переключает флажок, на котором стоит фокус.
  ///
  /// `Enter` не берётся: он подтверждает окно целиком, и отбирать его у формы
  /// ради флажка нельзя — заполнил и нажал `Enter` — это про окно, а не про
  /// последний тронутый контрол.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    widget.onChanged!(!widget.value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final enabled = _enabled;
    final value = widget.value;
    final label = widget.label;
    final onChanged = widget.onChanged;

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: enabled,
        skipTraversal: !enabled,
        onKeyEvent: _handleKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => onChanged!(!value) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: metrics.checkboxSize,
                    height: metrics.checkboxSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.inputBackground,
                      border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                      borderRadius: BorderRadius.circular(metrics.inputRadius),
                    ),
                    // Поверх, а не рамкой: знак поехал бы вместе с подписью.
                    // Слой стоит всегда — появление `foregroundDecoration`
                    // пересобирает то, что под ним.
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(
                        color: _focused ? colors.focusRing : const Color(0x00000000),
                        width: metrics.focusRingWidth,
                      ),
                      borderRadius: BorderRadius.circular(metrics.inputRadius),
                    ),
                    child:
                        value
                            ? Text(
                              theme.icons.glyph(theme.icons.check),
                              style: TextStyle(
                                fontFamily: theme.icons.fontFamily,
                                fontSize: metrics.fontSize * 0.8,
                                color: colors.inputText,
                              ),
                            )
                            : null,
                  ),
                  SizedBox(width: metrics.checkboxGap),
                  // Подпись уступает, если места мало: в форме флаг стоит в
                  // столбце значений, а тот бывает узким. Раньше флаг занимал
                  // всю ширину окна и упереться ему было не во что.
                  Flexible(
                    child:
                        widget.richLabel == null
                            ? FcText(label)
                            : Text.rich(widget.richLabel!, style: theme.dialogTextStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель: ровно один вариант из нескольких.
///
/// Варианты задаются картой «значение → метка»: порядок в ней и есть порядок
/// на экране.
class FcRadioGroup<T> extends StatefulWidget {
  const FcRadioGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.direction = Axis.vertical,
    this.focusNode,
  });

  final Map<T, String> options;
  final T? value;

  /// null — варианты показаны, но не меняются.
  final ValueChanged<T>? onChanged;

  final Axis direction;

  /// Узел фокуса — когда он нужен снаружи.
  final FocusNode? focusNode;

  @override
  State<FcRadioGroup<T>> createState() => _FcRadioGroupState<T>();
}

class _FcRadioGroupState<T> extends State<FcRadioGroup<T>> {
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  /// Стрелки ходят по вариантам, `Space` подтверждает тот, что под фокусом.
  ///
  /// Группа — **одна** остановка обхода, а не столько, сколько в ней вариантов:
  /// так устроен переключатель везде, и так он и читается — один вопрос, один
  /// ответ. Выйти из группы можно только `Tab`ом: стрелка, нажатая по привычке,
  /// не должна уводить фокус в кнопки.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final keys = widget.options.keys.toList();
    if (keys.isEmpty) {
      return KeyEventResult.ignored;
    }

    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.arrowLeft => -1,
      _ => 0,
    };
    if (step == 0) {
      return KeyEventResult.ignored;
    }

    // По кругу: дошли до последнего — следующая стрелка возвращает к первому.
    final current = keys.indexOf(widget.value as T);
    final next = (current < 0 ? 0 : (current + step + keys.length) % keys.length);
    widget.onChanged!(keys[next]);
    return KeyEventResult.handled;
  }

  /// Варианты разделены [FcMetrics.dialogGap] — тем же зазором, что строки
  /// окна и кнопки в его ряду: это расстояние **между контролами**.
  /// [FcMetrics.checkboxGap] здесь не годится, он про другое — про расстояние
  /// от знака до его метки, внутри одного варианта.
  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final options = widget.options;
    final value = widget.value;
    final direction = widget.direction;
    final items = <Widget>[
      for (final entry in options.entries)
        _FcRadioOption<T>(
          label: entry.value,
          selected: entry.key == value,
          // Обводка — у выбранного: он и есть ответ, на котором стоит фокус.
          focused: _focused && entry.key == value,
          onTap: widget.onChanged == null ? null : () => widget.onChanged!(entry.key),
        ),
    ];

    final Widget body;
    if (direction == Axis.vertical) {
      body = Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: metrics.dialogGap), items[i]],
          ],
        ),
      );
    } else {
      // Ряд, который переносится: сколько вариантов и какой ширины у них
      // подписи, модуль знает, а вот сколько места ему дадут — нет. Строка,
      // вылезающая за край окна, — не тот способ об этом сообщить.
      body = Wrap(spacing: metrics.dialogGap, runSpacing: metrics.dialogGap, children: items);
    }

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: _enabled,
      skipTraversal: !_enabled,
      onKeyEvent: _handleKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: body,
    );
  }
}

class _FcRadioOption<T> extends StatelessWidget {
  const _FcRadioOption({required this.label, required this.selected, required this.onTap, this.focused = false});

  final String label;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: metrics.checkboxSize,
                height: metrics.checkboxSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.inputBackground,
                  border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                  shape: BoxShape.circle,
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: focused ? colors.focusRing : const Color(0x00000000),
                    width: metrics.focusRingWidth,
                  ),
                  shape: BoxShape.circle,
                ),
                child:
                    selected
                        ? Container(
                          width: metrics.checkboxSize / 2.5,
                          height: metrics.checkboxSize / 2.5,
                          decoration: BoxDecoration(color: colors.inputText, shape: BoxShape.circle),
                        )
                        : null,
              ),
              SizedBox(width: metrics.checkboxGap),
              // Подпись уступает, если места мало — как и у флага.
              Flexible(child: FcText(label)),
            ],
          ),
        ),
      ),
    );
  }
}
