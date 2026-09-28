import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'markdown_viewer_screen.dart';

/// Показ markdown: свёрстанный документ или его исходник.
///
/// Вид **один на оба места** — во весь экран и в области панели, как у текста и
/// у картинок: разница в раме и в фокусе, и обе берутся у области.
class MarkdownViewerView extends StatelessWidget {
  const MarkdownViewerView({super.key, required this.screen});

  final MarkdownViewerScreen screen;

  /// `Esc` закрывает показ — он принадлежит оболочке. Стрелки крутят текст: в
  /// показе курсора не видно, и шагать им по строкам некому.
  static const FcTextShortcuts _shortcuts = FcTextShortcuts(
    released: {CodeShortcutType.esc, CodeShortcutType.copy},
    scrollsByArrows: true,
  );

  @override
  Widget build(BuildContext context) {
    // Приложение нужно только в панели: во весь экран рама и фокус известны и
    // так — оба края внешние, ввод его.
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder: (context, _) {
        final focused = app == null || app.view.takesKeys(screen);

        if (!screen.formatted) {
          return FcTextView(
            controller: screen.source,
            path: screen.entry.path,
            fileName: screen.entry.name,
            trailing: formatBytesLong(screen.entry.size),
            readOnly: true,
            shortcuts: _shortcuts,
            outerEdge: _edgeOf(app),
            focused: focused,
          );
        }

        final theme = FcTheme.of(context);

        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          // Документ занимает раму целиком: отступ внутри даёт сам показ, и
          // второй, от рамы, только съедал бы ширину строки.
          fillsFrame: true,
          header: FcPathPlate(path: screen.entry.path, trailing: formatBytesLong(screen.entry.size), active: focused),
          child: FcMarkdownView(
            document: screen.document,
            blocks: app?.markdownBlocks ?? const [],
            padding: EdgeInsets.symmetric(
              horizontal: theme.metrics.dialogPadding,
              vertical: theme.metrics.dialogLineGap,
            ),
            onTapLink: (_, href, _) => _openLink(href),
          ),
        );
      },
    );
  }

  /// Внешняя ссылка уходит системе.
  ///
  /// Переходов по внутренним ссылкам в этой версии нет
  /// (`docs/spec/markdown-viewer.md`, §9): они требуют решить, что происходит с
  /// панелью и историей.
  void _openLink(String? href) {
    final open = screen.openWith;
    if (href == null || href.isEmpty || open == null) {
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      unawaited(open(href));
    }
  }

  /// Внешние края рамы: во весь экран оба, в панели — её сторона.
  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }

    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }
}
