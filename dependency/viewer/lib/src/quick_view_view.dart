import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'quick_view_screen.dart';

/// Быстрый просмотр в области панели.
///
/// Своего показа у хозяина нет: он рисует то, что выбрал реестр, — тем же
/// видом, каким это рисуется во весь экран. Здесь остаётся одно: сказать
/// словами, когда показывать нечего.
class QuickViewView extends StatelessWidget {
  const QuickViewView({super.key, required this.host});

  final QuickViewHost host;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);

    // Щелчок в показ уводит туда ввод — как щелчок по панели
    // (`docs/spec/quick-view.md`, §5). `Listener`, а не жест: он слышит любое
    // нажатие и не спорит с жестами показа — потянутая полоса перемотки тоже
    // считается.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        final at = app.view.positionOf(host);
        if (at != null && app.view.activeArea != at) {
          app.view.setFocus(at);
        }
      },
      child: _shown(context, app),
    );
  }

  Widget _shown(BuildContext context, Application app) {
    return ListenableBuilder(
      listenable: Listenable.merge([host, app.view]),
      builder: (context, _) {
        final inner = host.inner;
        if (inner != null) {
          final build = app.views.builderFor(inner);
          if (build != null) {
            final shown = build(context, inner);
            // Пока читается следующий файл, показанное стоит как стояло —
            // мигать на каждом шаге курсора хуже, чем подождать молча. О том,
            // что чтение идёт, говорит подсказка: место для настоящего
            // указателя хода ещё не выбрано, а молчать вовсе нельзя.
            return host.loading == null ? shown : FcTooltip(message: host.loading!, child: shown);
          }
        }

        final theme = FcTheme.of(context);
        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          header: FcPathPlate(
            path:
                host.panel.currentEntry?.path.isNotEmpty == true
                    ? host.panel.currentEntry!.path
                    : (host.panel.currentPath.isEmpty ? '/' : host.panel.currentPath),
            active: app.view.takesKeys(host),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(theme.metrics.labelPadding),
              child: Text(host.notice ?? '', textAlign: TextAlign.center, style: theme.statusStyle),
            ),
          ),
        );
      },
    );
  }

  /// Сторона рамы: показ стоит на месте панели и выглядеть обязан так же.
  PanelOuterEdge _edgeOf(Application app) => switch (app.view.positionOf(host)) {
    ViewportPosition.left => PanelOuterEdge.left,
    ViewportPosition.right => PanelOuterEdge.right,
    _ => PanelOuterEdge.both,
  };
}
