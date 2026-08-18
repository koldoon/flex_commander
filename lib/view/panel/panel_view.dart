import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../state/panel_controller.dart';
import '../theme/app_theme.dart';
import 'file_table.dart';
import 'panel_path_header.dart';
import 'panel_status_bar.dart';

/// Внешний край окна, к которому прижата панель.
///
/// Единственное, зачем панели знать свою сторону: с этого края рамка не
/// рисуется. В референсе она там есть, но нарочно вынесена за край окна
/// (`left="-3"` у левой панели, `right="-3"` у правой) — видно её не должно быть.
enum PanelOuterEdge { left, right }

/// Панель целиком: «плашка» пути, таблица файлов и строка состояния.
///
/// О том, левая она или правая, панель знает только ради внешней рамки
/// ([outerEdge]); всё остальное у обеих одинаково, а какая из них активна,
/// решает [AppController].
class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.panel, this.outerEdge});

  final PanelController panel;

  final PanelOuterEdge? outerEdge;

  /// Рамка панели без той стороны, что смотрит на край окна.
  Border _border(FcTheme theme) {
    final side = BorderSide(color: theme.colors.panelBorder, width: theme.metrics.strokeWidth);
    return Border(
      top: side,
      bottom: side,
      left: outerEdge == PanelOuterEdge.left ? BorderSide.none : side,
      right: outerEdge == PanelOuterEdge.right ? BorderSide.none : side,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final app = AppScope.read(context);

    return PanelScope(
      panel: panel,
      child: GestureDetector(
        // Клик в любом месте панели делает её активной — поведение референса.
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => app.activate(panel),
        child: Stack(
          children: [
            Padding(
              // Верхняя половина «плашки» пути лежит над рамкой панели.
              padding: EdgeInsets.only(top: metrics.pathHeaderHeight / 2),
              child: Container(
                decoration: BoxDecoration(color: theme.colors.panelBackground, border: _border(theme)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // От рамки панели до строки заголовков: `top="80"` при
                    // рамке, начинающейся с `top="30"`.
                    SizedBox(height: metrics.panelTopPadding),
                    Expanded(child: FileTable(panel: panel)),
                    PanelStatusBar(panel: panel),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: metrics.pathHeaderMinInset,
              right: metrics.pathHeaderMinInset,
              child: Align(
                alignment: Alignment.topCenter,
                child: ListenableBuilder(
                  listenable: panel,
                  builder:
                      (context, _) => PanelPathHeader(path: panel.directory?.displayPath ?? '/', active: panel.active),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
