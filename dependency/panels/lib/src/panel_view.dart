import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
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

  final Panel panel;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final outerEdge =
        identical(panel, app.left)
            ? PanelOuterEdge.left
            : identical(panel, app.right)
            ? PanelOuterEdge.right
            : null;

    return PanelScope(
      panel: panel,
      child: GestureDetector(
        // Клик в любом месте панели делает её активной — поведение референса.
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => app.activate(panel),
        child: FcPanelFrame(
          outerEdge: outerEdge,
          header: ListenableBuilder(
            // И на область тоже: ввод уходит и туда, где панели нет вовсе, —
            // в быстрый просмотр напротив, — а плашка обязана это показать.
            listenable: Listenable.merge([panel, app.view]),
            builder:
                (context, _) => FcPathPlate(
                  path: panel.headerText ?? (panel.currentPath.isEmpty ? '/' : panel.currentPath),
                  // Не `panel.active`: та говорит, какая панель — **источник**
                  // операции, и остаётся собой, когда ввод ушёл в наложение
                  // напротив. Плашка говорит другое: где сейчас клавиши.
                  active: app.view.takesKeys(panel),
                ),
          ),
          footer: PanelStatusBar(panel: panel),
          // Не таблица файлов, а то, чем рисуется вид содержимого панели:
          // результаты поиска и просмотрщики — такие же жильцы панели, как и
          // файлы. Каталог же человек показывает как хочет — своим видом
          // (`docs/spec/panel-views.md`, §3).
          child: _content(context, app, panel),
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
Widget _content(BuildContext context, Application app, Panel panel) {
  if (panel.source.contentKind != SourceInfo.files) {
    return app.viewports.builderFor(panel.source.contentKind)(context, panel);
  }
  final view = app.panelViews.byId(panel.view);
  return view != null ? view.build(context, panel) : app.viewports.builderFor(SourceInfo.files)(context, panel);
}
