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
  final GlobalKey _swatch = GlobalKey();

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
    final box = _swatch.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
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
              width: metrics.dialogLabelWidth,
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
              child: _Swatch(key: _swatch, color: widget.value, size: metrics.inputHeight),
            ),
          ),
        ),
        SizedBox(width: metrics.columnGap),
        // Поле уступает, когда окно узко: иначе оно выдавливает образец за край.
        Flexible(child: widget.fieldWidth == null ? field : SizedBox(width: widget.fieldWidth, child: field)),
      ],
    );
  }
}

/// Квадрат цвета — с шахматкой под ним.
///
/// Шахматка обязательна: без неё `#00000000` и `#FF000000` выглядят одинаково,
/// и прозрачный цвет неотличим от чёрного (`docs/spec/theme-editor.md`, §4).
class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colors.inputBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _SwatchPainter(color: color, cell: metrics.iconSize / 2)),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.cell});

  final Color color;

  /// Сторона клетки шахматки.
  final double cell;

  /// Клетки — серым по белому, а не цветами темы: это не часть оформления, а
  /// условный знак «здесь просвечивает».
  static const Color _light = Color(0xFFFFFFFF);
  static const Color _dark = Color(0xFFBFBFBF);

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = _light;
    final dark = Paint()..color = _dark;
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.cell != cell;
}
