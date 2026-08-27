import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'quick_view_screen.dart';

/// Быстрый просмотр в области панели.
///
/// Показ тот же, что и во весь экран: `FcTextView` — рамка, плашка, поле,
/// подсветка, поиск. Своего показа текста здесь заводить нельзя: два показа
/// одного и того же однажды разойдутся, и это уже проверено на просмотрщике с
/// редактором.
///
/// Отличий от полноэкранного два, и оба про место: рамка внешняя со своей
/// стороны, а фокус просится, только когда в просмотр вошли, — пока курсор в
/// файловой панели, стрелки принадлежат ей.
class QuickViewView extends StatelessWidget {
  const QuickViewView({super.key, required this.screen});

  final QuickViewScreen screen;

  static const FcTextShortcuts _shortcuts = FcTextShortcuts(
    released: {CodeShortcutType.esc, CodeShortcutType.copy},
    scrollsByArrows: true,
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);

    return ListenableBuilder(
      listenable: Listenable.merge([screen, app.view]),
      builder: (context, _) {
        final position = _positionOf(app);
        final focused = position != null && app.view.activeArea == position;
        final notice = screen.notice;

        // Рамку и плашку рисует показ текста сам — тот же `FcPanelFrame`, что
        // у панели. Своя рама здесь только там, где текста нет вовсе.
        if (notice != null) {
          final theme = FcTheme.of(context);
          return FcPanelFrame(
            outerEdge: _edgeOf(position),
            header: FcPathPlate(path: screen.node.displayPath, active: focused),
            // Причина — словами и в самой панели: тост на каждом шаге курсора
            // мигал бы всю дорогу.
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(theme.metrics.labelPadding),
                child: Text(notice, textAlign: TextAlign.center, style: theme.statusStyle),
              ),
            ),
          );
        }

        return FcTextView(
          controller: screen.controller,
          finder: screen.finder,
          path: screen.node.displayPath,
          fileName: screen.node.name,
          trailing: formatBytesLong(screen.node.size),
          readOnly: true,
          wordWrap: screen.wordWrap,
          showLineNumbers: screen.showLineNumbers,
          shortcuts: _shortcuts,
          outerEdge: _edgeOf(position),
          focused: focused,
        );
      },
    );
  }

  /// В какой области нас показывают: сторона нужна рамке.
  ViewportPosition? _positionOf(Application app) {
    for (final position in [ViewportPosition.left, ViewportPosition.right]) {
      if (identical(app.view.contentAt(position), screen)) {
        return position;
      }
    }
    return null;
  }

  PanelOuterEdge _edgeOf(ViewportPosition? position) => switch (position) {
    ViewportPosition.left => PanelOuterEdge.left,
    ViewportPosition.right => PanelOuterEdge.right,
    _ => PanelOuterEdge.both,
  };
}
