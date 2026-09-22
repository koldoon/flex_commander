import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';

import 'command_dialog.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

/// Цвет: образец слева, `#AARRGGBB` справа, палитра за образцом.
///
/// Своим списком, а не системным окном выбора цвета: системное выглядит в
/// приложении чужим и на Linux бывает не тем, что на macOS
/// (`docs/spec/theme-editor.md`, §4).
class FcColorField extends StatefulWidget {
  const FcColorField({
    super.key,
    required this.controller,
    required this.value,
    required this.onChanged,
    this.palette = const [],
    this.fieldWidth,
    this.focusNode,
  });

  /// Набранное живёт снаружи — столько же, сколько окно: возврат к умолчанию
  /// меняет значение помимо набора, и поле обязано это показать.
  final TextEditingController controller;

  /// Что стоит сейчас — им красится образец.
  ///
  /// Отдельно от [controller]: пока набрано недописанное (`#FF2`), цвет ещё
  /// прежний, и образец показывает именно его.
  final Color value;

  final ValueChanged<Color> onChanged;

  /// Что предложить за образцом; пусто — образец не нажимается.
  ///
  /// Нажатие без ответа неотличимо от промаха, поэтому у пустой палитры
  /// образец не берёт ни курсора, ни щелчка.
  final List<Color> palette;

  /// Ширина поля ввода; null — во всю доступную.
  final double? fieldWidth;

  final FocusNode? focusNode;

  @override
  State<FcColorField> createState() => _FcColorFieldState();
}

class _FcColorFieldState extends State<FcColorField> {
  /// Сколько образцов видно, пока палитра не начнёт прокручиваться.
  static const int _visibleRows = 10;

  final LayerLink _link = LayerLink();

  /// Поле ввода — по нему палитре задаётся ширина.
  ///
  /// По полю, а не по образцу и не по всей строке: под образцом в строку
  /// палитры помещалось три знака из девяти, а строка в форме настроек
  /// растянута на всю колонку — палитра во всю колонку и раскрывалась.
  final GlobalKey _field = GlobalKey();

  /// Ширина палитры, замеренная при раскрытии; 0 — палитра закрыта.
  double _width = 0;

  OverlayEntry? _palette;

  bool get _open => _palette != null;

  bool get _pickable => widget.palette.isNotEmpty;

  @override
  void dispose() {
    _palette?.remove();
    _palette = null;
    super.dispose();
  }

  void _close() {
    _palette?.remove();
    setState(() => _palette = null);
  }

  void _choose(Color color) {
    _close();
    final text = formatColor(color);
    widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    widget.onChanged(color);
  }

  /// Раскрывает палитру **под образцом**: она продолжает его, а не всплывает у
  /// курсора, — так же, как раскрывается список выбора.
  void _openPalette() {
    if (_open || !_pickable) {
      return;
    }
    final box = _field.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    // От левого края образца до правого края поля: палитра продолжает поле, а
    // не колонку, в которой оно стоит.
    final theme = FcTheme.of(context);
    _width = theme.metrics.inputHeight + theme.metrics.columnGap + box.size.width;
    final entry = OverlayEntry(builder: (context) => _dropdown(context));
    Overlay.of(context).insert(entry);
    setState(() => _palette = entry);
  }

  Widget _dropdown(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final line = metrics.rowHeight + metrics.rowGap;
    final chosen = widget.palette.indexOf(widget.value);

    return Stack(
      children: [
        // Щелчок мимо закрывает — так же, как затенение закрывает окно.
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: Offset(0, metrics.dialogLineGap),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: _width,
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
                rows: [
                  for (final color in widget.palette)
                    FcPickRow(
                      id: formatColor(color),
                      // Имени у цвета нет: он и есть своя запись. Образец —
                      // значком справа: словами цвет не пересказать.
                      title: formatColor(color),
                      badge: _Swatch(color: color, size: theme.metrics.iconSize),
                    ),
                ],
                query: '',
                textInset: metrics.inputHorizontalPadding,
                // Стоящего в палитре может и не быть: цвет набирают руками.
                selected: chosen < 0 ? 0 : chosen,
                onTap: (id) {
                  if (parseColor(id) case final color?) {
                    _choose(color);
                  }
                },
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

    final field = FcTextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      // Набранное, которое цветом не является, просто не применяется: ругаться
      // на `#FF2` посреди набора хуже, чем подождать, пока человек допишет.
      onChanged: (text) {
        if (parseColor(text) case final color?) {
          widget.onChanged(color);
        }
      },
    );

    return Row(
      children: [
        CompositedTransformTarget(
          link: _link,
          child: MouseRegion(
            cursor: _pickable ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickable ? (_open ? _close : _openPalette) : null,
              child: _Swatch(color: widget.value, size: metrics.inputHeight),
            ),
          ),
        ),
        SizedBox(width: metrics.columnGap),
        // Поле уступает, когда окно узко: иначе оно выдавливает образец за край.
        Flexible(
          child: KeyedSubtree(
            key: _field,
            child: widget.fieldWidth == null ? field : SizedBox(width: widget.fieldWidth, child: field),
          ),
        ),
      ],
    );
  }
}

/// Квадрат цвета — с шахматкой под ним.
///
/// Шахматка обязательна: без неё `#00000000` и `#FF000000` выглядят одинаково,
/// и прозрачный цвет неотличим от чёрного (`docs/spec/theme-editor.md`, §4).
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SwatchPainter(
          color: color,
          cell: metrics.iconSize / 2,
          // Скругление вдвое мельче, чем у поля рядом: образец — его приставка,
          // а не второе поле.
          radius: metrics.inputRadius / 2,
        ),
      ),
    );
  }
}

/// Рисует образец сам — скруглением кисти, а не обрезкой снаружи.
///
/// Обрезка со сглаживанием берёт на углах покрытие наполовину, и берёт его
/// **каждый слой порознь**: белая подложка шахматки проступала сквозь
/// непрозрачный цвет светлыми уголками, неотличимыми от обводки. Одна фигура
/// одной кистью этого не умеет.
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.cell, required this.radius});

  final Color color;

  /// Сторона клетки шахматки.
  final double cell;

  /// Скругление углов образца.
  final double radius;

  /// Клетки — серым по белому, а не цветами темы: это не часть оформления, а
  /// условный знак «здесь просвечивает».
  static const Color _light = Color(0xFFFFFFFF);
  static const Color _dark = Color(0xFFBFBFBF);

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));

    // Шахматка — только под просвечивающим: под непрозрачным её не видно, а
    // подмешаться на сглаженных углах она успевает.
    if (color.a < 1) {
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(Offset.zero & size, Paint()..color = _light);
      for (var y = 0.0; y < size.height; y += cell) {
        for (var x = 0.0; x < size.width; x += cell) {
          if (((x / cell).floor() + (y / cell).floor()).isOdd) {
            canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), Paint()..color = _dark);
          }
        }
      }
      canvas.restore();
    }

    canvas.drawRRect(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.cell != cell || old.radius != radius;
}
