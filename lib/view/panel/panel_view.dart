import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../state/panel_controller.dart';
import '../theme/app_theme.dart';
import 'file_table.dart';
import 'panel_path_header.dart';
import 'panel_status_bar.dart';

/// Панель целиком: «плашка» пути, таблица файлов и строка состояния.
///
/// Не знает, левая она или правая: обе панели устроены одинаково, а какая из
/// них активна, решает [AppController].
class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.panel});

  final PanelController panel;

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
                decoration: BoxDecoration(
                  color: theme.colors.panelBackground,
                  border: Border.all(color: theme.colors.panelBorder, width: metrics.strokeWidth),
                ),
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
                      (context, _) => PanelPathHeader(path: panel.directory?.pathString ?? '/', active: panel.active),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
