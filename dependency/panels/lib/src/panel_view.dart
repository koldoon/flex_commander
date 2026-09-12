import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'history_arrows.dart';
import 'panel_status_bar.dart';

/// Панель целиком: «плашка» пути, таблица файлов и строка состояния.
///
/// Рамку и плашку рисует общий [FcPanelFrame] из API — тот же, которым
/// пользуется просмотрщик: место в окне у них одно и то же, и выглядеть они
/// обязаны одинаково.
///
/// О том, левая она или правая, панель знает только ради внешней рамки; всё
/// остальное у обеих одинаково, а какая из них активна, решает приложение.
///
/// Сторону панель выводит сама, а не получает параметром: вид её строит реестр,
/// а он передаёт только состояние — про место в окне ему знать неоткуда.
class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.panel});

  final Session panel;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    // Край берётся у **места**, а не у сессии: одна и та же сессия бывает
    // показана в обеих панелях (`docs/spec/panel-sessions.md`, §7), и по ней
    // левая от правой не отличается.
    final at = ViewportScope.maybeOf(context);
    final outerEdge = switch (at) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => null,
    };

    return PanelScope(
      panel: panel,
      child: GestureDetector(
        // Клик в любом месте панели делает её активной — поведение референса.
        // Активной становится **эта** панель: щёлкнули по месту, а не по
        // сессии, и показанная в обеих сторонах не должна уводить ввод туда,
        // где он был.
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => at == null ? app.activate(panel) : app.view.setFocus(at),
        child: FcPanelFrame(
          outerEdge: outerEdge,
          header: ListenableBuilder(
            // И на область тоже: ввод уходит и туда, где панели нет вовсе, —
            // в быстрый просмотр напротив, — а плашка обязана это показать.
            listenable: Listenable.merge([panel, app.view]),
            builder:
                (context, _) => FcPathPlate(
                  path: panel.headerText ?? (panel.currentPath.isEmpty ? '/' : panel.currentPath),
                  // «Назад» и «вперёд» — только у панели с файлами: у
                  // просмотрщика в этой же плашке истории нет
                  // (`docs/spec/session-history.md`, §9).
                  leading: HistoryArrows(panel: panel),
                  // Не `panel.active`: та говорит, какая **сессия** —
                  // источник операции, и остаётся собой, когда ввод ушёл в
                  // наложение напротив, а показана она бывает сразу в обеих
                  // панелях. Плашка говорит другое: где сейчас клавиши.
                  active: takesKeysHere(context, panel),
                ),
          ),
          footer: PanelStatusBar(panel: panel),
          // Не таблица файлов, а то, чем рисуется вид содержимого панели:
          // результаты поиска и просмотрщики — такие же жильцы панели, как и
          // файлы. Каталог же человек показывает как хочет — своим видом
          // (`docs/spec/panel-views.md`, §3).
          // Слушает панель: вид выбирает человек (`Cmd-1`…`Cmd-3`), а
          // содержимое — источник, и меняются оба на ходу. Без подписки
          // содержимое оставалось прежним до первой чужой перерисовки — живьём
          // вид не менялся, пока не нажмёшь `Tab`.
          child: ListenableBuilder(listenable: panel, builder: (context, _) => _content(context, app, panel)),
        ),
      ),
    );
  }
}

/// Чем рисовать то, что в панели сейчас.
///
/// Источник со своим видом содержимого главнее выбора человека: список находок
/// останется списком находок, чем бы его ни просили рисовать. Каталог рисуется
/// выбранным видом, а незнакомый вид — таблицей: модуль, объявивший вид, могли
/// выключить, а показать каталог панель обязана.
Widget _content(BuildContext context, Application app, Session panel) {
  if (panel.source.contentKind != SourceInfo.files) {
    return app.viewports.builderFor(panel.source.contentKind)(context, panel);
  }
  final view = app.panelViews.byId(panel.view);
  return view != null ? view.build(context, panel) : app.viewports.builderFor(SourceInfo.files)(context, panel);
}
