import 'package:flutter/material.dart';

import 'fc_theme.dart';
import 'text_trim.dart';

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
  const FcPathPlate({
    super.key,
    required this.path,
    this.leading,
    this.leadingWidth = 0,
    this.trailing,
    this.active = true,
  });

  final String path;

  /// Что стоит слева от пути; null — только путь.
  ///
  /// Слотом, а не встройкой: плашкой пользуется всё, что занимает место в
  /// окне, — панель, просмотрщик, редактор, — а стрелки «назад» и «вперёд»
  /// есть только у панели (`docs/spec/session-history.md`, §9).
  final Widget? leading;

  /// Сколько места занимает слот.
  ///
  /// Числом, а не замером: **плашка обрезает путь сама**, и мерить обязана
  /// тем же, чем рисует, — до раскладки. Не зная ширины слота, она отмерила бы
  /// путь по всей плашке, и конец пути ушёл бы за край, обрезанный уже не с
  /// головы, а с хвоста. Ширину называет тот, кто слот даёт: она у него
  /// известна (`HistoryArrows.widthOf`).
  final double leadingWidth;

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
    // Тем же стилем, каким будет набрано: плашка меряет путь сама, и мерить
    // не то, что рисуется, значит срезать хвост пути ровно на разрядку
    // окружения ([FcTheme.effective]).
    final style = FcTheme.effective(
      context,
      active ? theme.pathStyle : theme.pathStyle.copyWith(color: colors.pathInactiveText),
    );

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

            // Что остаётся пути: вся плашка минус слот с его зазором и минус
            // приписка.
            final free =
                constraints.maxWidth -
                (leading == null ? 0 : leadingWidth + metrics.labelPadding) -
                (suffix == null ? 0 : textWidthOf(_gap + suffix, style, scaler));

            // Сдвига, как в строках списка, здесь нет: он нужен моноширинному
            // шрифту, а путь набран Ubuntu — у него базовая линия обычная.
            final pathText = Text(
              trimTextHead(path, style, free, scaler),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: style,
            );

            if (suffix == null && leading == null) {
              return Center(widthFactor: 1, child: pathText);
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading case final slot?) ...[slot, SizedBox(width: metrics.labelPadding)],
                Flexible(child: pathText),
                // Приписка тоже гнётся: в узкой панели её одной хватало, чтобы
                // плашка вылезла за края. Путь к тому времени ужат уже до
                // ничего, и ужиматься дальше некому.
                if (suffix != null)
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

  /// «Плашка» поверх верхней рамки; null — рамка без заголовка, и места под
  /// плашку не остаётся.
  ///
  /// Без заголовка раму берёт то, чьё имя и так очевидно из места: список
  /// фоновых работ стоит под своей панелью, и подписывать его нечем.
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
    final border = _border(theme);
    // Скругление — только у замкнутой рамки. Дело не в красоте: `BoxDecoration`
    // с разными сторонами и радиусом не рисуется вовсе, а у прижатой к краю
    // панели одна сторона не рисуется.
    final radius = border.isUniform && metrics.panelRadius > 0 ? BorderRadius.circular(metrics.panelRadius) : null;

    return Stack(
      children: [
        Padding(
          // Верхняя половина «плашки» лежит над рамкой — и место под неё
          // оставляется, только если плашка есть. Раме без заголовка этот
          // отступ был бы полосой пустоты над скруглённым краем.
          padding: EdgeInsets.only(top: header == null ? 0 : metrics.pathHeaderHeight / 2),
          child: Container(
            // Содержимое обрезается по той же дуге: строка под курсором иначе
            // вылезала бы за угол прямым краем.
            clipBehavior: radius == null ? Clip.none : Clip.antiAlias,
            decoration: BoxDecoration(color: theme.colors.panelBackground, border: border, borderRadius: radius),
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
