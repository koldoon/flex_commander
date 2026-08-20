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
class FcCheckbox extends StatelessWidget {
  const FcCheckbox({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;

  /// null — флажок показан, но не меняется.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final enabled = onChanged != null;

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
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
                FcText(label),
              ],
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
class FcRadioGroup<T> extends StatelessWidget {
  const FcRadioGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.direction = Axis.vertical,
  });

  final Map<T, String> options;
  final T? value;

  /// null — варианты показаны, но не меняются.
  final ValueChanged<T>? onChanged;

  final Axis direction;

  /// Варианты разделены [FcMetrics.dialogGap] — тем же зазором, что строки
  /// окна и кнопки в его ряду: это расстояние **между контролами**.
  /// [FcMetrics.checkboxGap] здесь не годится, он про другое — про расстояние
  /// от знака до его метки, внутри одного варианта.
  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final items = <Widget>[
      for (final entry in options.entries)
        _FcRadioOption<T>(
          label: entry.value,
          selected: entry.key == value,
          onTap: onChanged == null ? null : () => onChanged!(entry.key),
        ),
    ];

    if (direction == Axis.vertical) {
      return Align(
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
    }

    // Ряд, который переносится: сколько вариантов и какой ширины у них подписи,
    // модуль знает, а вот сколько места ему дадут — нет. Строка, вылезающая за
    // край окна, — не тот способ об этом сообщить.
    return Wrap(spacing: metrics.dialogGap, runSpacing: metrics.dialogGap, children: items);
  }
}

class _FcRadioOption<T> extends StatelessWidget {
  const _FcRadioOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
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
              FcText(label),
            ],
          ),
        ),
      ),
    );
  }
}
