import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'command_dialog.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

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

/// Выпадающий список: ровно один вариант из нескольких.
///
/// Выглядит как поле ввода — та же рамка, высота и отступы: и то и другое
/// отвечает на вопрос «что здесь стоит», и выглядеть они должны одинаково.
/// Отличает его галочка справа.
///
/// **Ширина — по самому длинному варианту**, а не во всю строку: список
/// показывает одно значение, и растянутый на полокна он обещал бы место,
/// которому там нечем заполниться.
///
/// **Раскрывается своим списком** ([FcPickList]) — тем же, что в палитре
/// команд, истории адресов и оглавлении настроек. Системное меню выглядело бы
/// здесь чужим: в приложении уже есть свой вид списка, и второй ему не нужен.
///
/// **Радиокнопок в приложении не бывает вовсе**: выбор одного из нескольких
/// делается этим списком, а там, где вариантов два, — флагом. Переключатель в
/// наборе был и удалён, чтобы не появиться снова.
///
/// Варианты задаются картой «значение → метка»: порядок в ней и есть порядок в
/// списке.
class FcSelect<T> extends StatefulWidget {
  const FcSelect({super.key, required this.options, required this.value, required this.onChanged, this.focusNode});

  final Map<T, String> options;

  /// Выбранное; null — не выбрано ничего, и поле пусто.
  final T? value;

  /// null — выбирать нельзя: список приглушён и фокуса не берёт.
  final ValueChanged<T>? onChanged;

  final FocusNode? focusNode;

  @override
  State<FcSelect<T>> createState() => _FcSelectState<T>();
}

class _FcSelectState<T> extends State<FcSelect<T>> {
  /// Сколько вариантов видно, пока список не начнёт прокручиваться.
  static const int _visibleRows = 10;

  final LayerLink _link = LayerLink();

  /// Сама рамка — не весь контрол.
  ///
  /// Содержимое окна выкладывается растягивающей колонкой, поэтому внешний бокс
  /// у списка во всю её ширину, а видимая рамка облегает содержимое. Раскрытую
  /// часть надо мерить по рамке: иначе она вылезала бы из-под поля во всю
  /// колонку.
  final GlobalKey _frame = GlobalKey();

  bool _focused = false;
  OverlayEntry? _menu;

  /// На чём стоит выбор в раскрытом списке — номер в [_values].
  int _highlighted = 0;

  bool get _enabled => widget.onChanged != null;

  bool get _open => _menu != null;

  List<T> get _values => widget.options.keys.toList();

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  /// Клавиши раскрытого и закрытого списка — разные.
  ///
  /// Закрытый переключает стрелками, не раскрываясь: так соседнее значение
  /// берут, не глядя. Раскрытый ими ходит по списку, а берёт по `Enter`.
  ///
  /// `Enter` у закрытого не отнимается: он подтверждает окно целиком, и
  /// забирать его у формы ради контрола нельзя — то же правило, что у флажка.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final values = _values;
    final key = event.logicalKey;

    if (_open) {
      switch (key) {
        case LogicalKeyboardKey.escape:
          _close();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
          _choose(values[_highlighted]);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown when _highlighted + 1 < values.length:
          _moveTo(_highlighted + 1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp when _highlighted > 0:
          _moveTo(_highlighted - 1);
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final at = values.indexOf(widget.value as T);
    switch (key) {
      case LogicalKeyboardKey.space:
        _openMenu();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown when at >= 0 && at + 1 < values.length:
        widget.onChanged!(values[at + 1]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when at > 0:
        widget.onChanged!(values[at - 1]);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveTo(int index) {
    _highlighted = index;
    _menu?.markNeedsBuild();
  }

  void _choose(T value) {
    _close();
    widget.onChanged?.call(value);
  }

  void _close() {
    _menu?.remove();
    setState(() => _menu = null);
  }

  /// Раскрывает список **под полем**: он продолжает поле, а не всплывает у
  /// курсора.
  void _openMenu() {
    if (_open) {
      return;
    }
    final box = _frame.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    _highlighted = _values.indexOf(widget.value as T).clamp(0, _values.length - 1);
    final width = box.size.width;
    final entry = OverlayEntry(builder: (context) => _dropdown(context, width));
    Overlay.of(context).insert(entry);
    setState(() => _menu = entry);
  }

  Widget _dropdown(BuildContext context, double width) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final values = _values;
    final line = metrics.rowHeight + metrics.rowGap;

    return Stack(
      children: [
        // Щелчок мимо закрывает — так же, как затенение закрывает окно.
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: Offset(0, metrics.dialogLineGap),
          // Без выравнивания вокруг: оно растянуло бы раскрытую часть на весь
          // экран, а ширину ей задаёт рамка поля.
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: line * _visibleRows),
              decoration: BoxDecoration(
                color: colors.dialogBackground,
                border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                borderRadius: BorderRadius.circular(metrics.inputRadius),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    offset: Offset(0, metrics.dialogShadowOffset),
                    blurRadius: metrics.dialogShadowBlur,
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(vertical: metrics.rowGap),
              child: FcPickList(
                rows: [for (final entry in widget.options.entries) FcPickRow(id: '${entry.key}', title: entry.value)],
                // Отбирать нечего: варианты уже перечислены, и подсветка
                // совпавшего была бы ответом на незаданный вопрос.
                query: '',
                textInset: metrics.inputHorizontalPadding,
                selected: _highlighted,
                onTap: (id) => _choose(values.firstWhere((value) => '$value' == id)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final enabled = _enabled;

    return CompositedTransformTarget(
      link: _link,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: enabled,
        skipTraversal: !enabled,
        onKeyEvent: _handleKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        // Облегает содержимое, как кнопка и флажок: содержимое окна
        // выкладывается растягивающей колонкой, и без этого список занял бы всю
        // её ширину.
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: MouseRegion(
              cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? (_open ? _close : _openMenu) : null,
                child: Container(
                  key: _frame,
                  height: metrics.inputHeight,
                  padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
                  decoration: BoxDecoration(
                    color: colors.inputBackground,
                    border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                    borderRadius: BorderRadius.circular(metrics.inputRadius),
                  ),
                  // Поверх, а не рамкой: рамка входит в размер и сдвигала бы
                  // соседей при появлении.
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: _focused ? colors.focusRing : const Color(0x00000000),
                      width: metrics.focusRingWidth,
                    ),
                    borderRadius: BorderRadius.circular(metrics.inputRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ширина — по самому длинному варианту, чтобы поле не
                      // прыгало при смене выбранного.
                      SizedBox(
                        width: widestLabel(context, widget.options.values),
                        child: Text(
                          widget.options[widget.value] ?? '',
                          style: theme.inputStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: metrics.columnGap),
                      Text(
                        theme.icons.glyph(theme.icons.caretDown),
                        style: TextStyle(
                          fontFamily: theme.icons.fontFamily,
                          fontSize: metrics.fontSize,
                          color: colors.inputText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
