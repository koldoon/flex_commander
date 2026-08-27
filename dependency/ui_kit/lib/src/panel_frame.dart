import 'package:flutter/material.dart';

import 'fc_theme.dart';

/// Внешний край окна, к которому прижата панель.
///
/// Единственное, зачем панели знать свою сторону: с этого края рамка не
/// рисуется. В референсе она там есть, но нарочно вынесена за край окна
/// (`left="-3"` у левой панели, `right="-3"` у правой) — видно её не должно
/// быть.
enum PanelOuterEdge {
  left,
  right,

  /// Оба края сразу — у того, что занимает всю ширину окна: просмотрщика,
  /// редактора, результатов поиска.
  both,
}

/// «Плашка» с путём: скруглённый прямоугольник, облегающий содержимое.
///
/// Живёт в API, потому что так выглядит **любое** место в приложении, а не
/// только файловая панель: просмотрщик и редактор занимают её место и обязаны
/// выглядеть так же.
class FcPathPlate extends StatelessWidget {
  const FcPathPlate({super.key, required this.path, this.trailing, this.active = true});

  final String path;

  /// Приписка справа — размер файла у просмотрщика; null — только путь.
  final String? trailing;

  /// Приглушённая плашка у неактивной панели.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

    // Активность панели в референсе плашкой не показывалась, но панелей две:
    // видеть, какая из них принимает клавиши, нужно, и приглушённая плашка —
    // самый спокойный способ это сказать.
    final style = active ? theme.pathStyle : theme.pathStyle.copyWith(color: colors.pathInactiveText);

    return Tooltip(
      message: trailing == null ? path : '$path  $trailing',
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: metrics.pathHeaderHeight,
        padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding),
        // Без alignment: иначе Container растянулся бы на всю доступную
        // ширину, а плашка должна облегать путь.
        decoration: BoxDecoration(
          color: active ? colors.pathBackground : colors.pathInactiveBackground,
          border: Border.all(color: colors.pathBorder, width: metrics.strokeWidth),
          borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            final suffix = trailing;

            // Сдвига, как в строках списка, здесь нет: он нужен Consolas,
            // а путь набран Ubuntu — у него базовая линия обычная.
            final pathText = Text(
              _trimHead(
                path,
                style,
                constraints.maxWidth - (suffix == null ? 0 : _widthOf(_gap + suffix, style, scaler)),
                scaler,
              ),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: style,
            );

            if (suffix == null) {
              return Center(widthFactor: 1, child: pathText);
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: pathText),
                // Приписка тоже гнётся: в узкой панели её одной хватало, чтобы
                // плашка вылезла за края. Путь к тому времени ужат уже до
                // ничего, и ужиматься дальше некому.
                Flexible(
                  child: Text(
                    _gap + suffix,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(color: colors.secondaryText),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Просвет между путём и припиской.
  static const String _gap = '   ';

  static double _widthOf(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Обрезает путь **слева**: конец строки важнее — в нём текущий каталог.
  ///
  /// Считается вручную, а не через `TextOverflow.ellipsis`: тот всегда режет
  /// хвост, а разворот направления текста ломает порядок символов в пути.
  static String _trimHead(String value, TextStyle style, double maxWidth, TextScaler scaler) {
    if (maxWidth.isInfinite || maxWidth <= 0) {
      return value;
    }

    if (_widthOf(value, style, scaler) <= maxWidth) {
      return value;
    }

    // Двоичный поиск самого длинного хвоста, который помещается вместе с «…».
    var low = 0;
    var high = value.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_widthOf('…${value.substring(middle)}', style, scaler) <= maxWidth) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return '…${value.substring(low)}';
  }
}

/// Оформление места в окне: обведённая область с «плашкой» заголовка,
/// наполовину заходящей на верхнюю рамку.
///
/// Так выглядит файловая панель — и так же обязано выглядеть всё, что занимает
/// её место: просмотрщик, редактор, результаты поиска. Поэтому рамка живёт в
/// API, а не в модуле панелей: иначе каждый следующий экран рисовал бы её
/// заново и однажды разошёлся бы на пиксель.
class FcPanelFrame extends StatelessWidget {
  const FcPanelFrame({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.outerEdge,
    this.fillsFrame = false,
  });

  /// Содержимое: таблица файлов, текст, что угодно.
  final Widget child;

  /// «Плашка» поверх верхней рамки; null — рамка без заголовка.
  final Widget? header;

  /// Строка под содержимым, внутри рамки.
  final Widget? footer;

  /// С какой стороны рамка упирается в край окна.
  final PanelOuterEdge? outerEdge;

  /// Содержимое занимает раму целиком, а плашка ложится поверх него.
  ///
  /// Обычно под плашкой оставлено место, и не зря: список файлов начинается
  /// строкой, и накрывать её заголовком нельзя. А **сплошное** содержимое —
  /// картинка — от этого только теряет: сверху остаётся полоса фона, тогда как
  /// показывать можно было всю раму. Плашке там ничего не мешает: у неё свой
  /// фон, и лежит она поверх.
  final bool fillsFrame;

  Border _border(FcTheme theme) {
    final side = BorderSide(color: theme.colors.panelBorder, width: theme.metrics.strokeWidth);

    // Внешний край не рисуется, **пока он и правда край окна**: там рамке не
    // от чего отделять, а лишняя черта вплотную к границе выглядит обводкой
    // самого окна.
    //
    // Появились поля по краям (`windowSidePadding`) — край перестал быть
    // краем, и рамка обязана замкнуться: иначе в отступе видна открытая
    // сторона панели.
    final flush = theme.metrics.windowSidePadding == 0;
    final openLeft = flush && (outerEdge == PanelOuterEdge.left || outerEdge == PanelOuterEdge.both);
    final openRight = flush && (outerEdge == PanelOuterEdge.right || outerEdge == PanelOuterEdge.both);

    return Border(
      top: side,
      bottom: side,
      left: openLeft ? BorderSide.none : side,
      right: openRight ? BorderSide.none : side,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Stack(
      children: [
        Padding(
          // Верхняя половина «плашки» лежит над рамкой.
          padding: EdgeInsets.only(top: metrics.pathHeaderHeight / 2),
          child: Container(
            decoration: BoxDecoration(color: theme.colors.panelBackground, border: _border(theme)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // От рамки до содержимого: `top="80"` при рамке, начинающейся
                // с `top="30"`. Сплошному содержимому этот отступ не нужен — и
                // мешает: оно рисуется во всю раму, а плашка ложится поверх.
                if (!fillsFrame) SizedBox(height: metrics.panelTopPadding),
                Expanded(child: child),
                if (footer case final footer?) footer,
              ],
            ),
          ),
        ),
        if (header case final header?)
          Positioned(
            top: 0,
            left: metrics.pathHeaderMinInset,
            right: metrics.pathHeaderMinInset,
            child: Align(alignment: Alignment.topCenter, child: header),
          ),
      ],
    );
  }
}
