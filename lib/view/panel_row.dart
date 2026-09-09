import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import '../state/commands/session_commands.dart';

/// Ряд открытых наборов — над **обеими** панелями
/// (`docs/spec/panel-sessions.md`, §3).
///
/// Рисует его шелл, а не модуль панелей: набор не принадлежит стороне, и ряд
/// над одной панелью врал бы об этом устройстве.
///
/// **Пока показано всё, ряда нет.** Полоса, которая ничего не выбирает, отняла
/// бы строку у списка файлов: при двух наборах оба и так на виду. Появляется
/// она с первым же непоказанным набором и пропадает вместе с ним.
class PanelRow extends StatelessWidget {
  const PanelRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    // Две подписки, и обе нужны. Внешняя — на приложение: от него меняется
    // **состав** ряда и то, что где показано. Внутренняя — на сами сессии: от
    // них меняются заголовки, а собирается она заново на каждый состав, иначе
    // заведённый только что набор никто не слушает и его имя застывает тем,
    // каким было при заведении.
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final panels = app.panels;
        final left = app.panelAt(ViewportPosition.left);
        final right = app.panelAt(ViewportPosition.right);
        if (!panels.any((panel) => !identical(panel, left) && !identical(panel, right))) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: Listenable.merge([for (final panel in panels) panel.session]),
          builder: (context, _) => _row(context, app, panels, left, right),
        );
      },
    );
  }

  Widget _row(BuildContext context, Application app, List<Panel> panels, Panel left, Panel right) {
    final metrics = FcTheme.of(context).metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.areaGap),
      child: SizedBox(
        height: metrics.headerRowHeight,
        child: Row(
          children: [
            for (var at = 0; at < panels.length; at++) ...[
              if (at > 0) SizedBox(width: metrics.strokeWidth),
              Flexible(
                child: _PanelChip(
                  number: at + 1,
                  title: panelTitle(panels[at], panels),
                  path: panels[at].session.currentPath,
                  shownLeft: identical(panels[at], left),
                  shownRight: identical(panels[at], right),
                  // Показывают в активной панели: ряд общий, и «куда» решает
                  // не он, а то, где сейчас курсор.
                  onTap: () => app.showPanel(app.view.sourceArea, panels[at]),
                  onClose: () => app.closePanel(panels[at]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Один набор в ряду: номер, имя и метки сторон, где он показан.
///
/// Метки — полосками по краям, а не буквами: слева показан — полоска слева,
/// справа — справа, в обеих — с обеих сторон. Знаком это пришлось бы читать,
/// а полоску видно, не читая.
class _PanelChip extends StatelessWidget {
  const _PanelChip({
    required this.number,
    required this.title,
    required this.path,
    required this.shownLeft,
    required this.shownRight,
    required this.onTap,
    required this.onClose,
  });

  final int number;
  final String title;
  final String path;
  final bool shownLeft;
  final bool shownRight;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final shown = shownLeft || shownRight;

    Widget mark(bool lit) =>
        SizedBox(width: metrics.markedBarWidth, child: lit ? ColoredBox(color: colors.markedBar) : null);

    return Tooltip(
      // Полный путь — подсказкой: имена в ряду короткие и повторяются
      // (`spec/panel-sessions.md`, §8).
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Средняя кнопка закрывает — привычка браузера, и стоит она недорого.
        onTertiaryTapUp: (_) => onClose(),
        child: Container(
          // Полоски сторон обрезаются по скруглению: рамке они не годятся —
          // скруглённая рамка бывает только одноцветной.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: shown ? colors.pathBackground : colors.panelBackground,
            border: Border.all(color: shown ? colors.pathBorder : colors.panelBorder, width: metrics.strokeWidth),
            borderRadius: BorderRadius.circular(metrics.inputRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              mark(shownLeft),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding * 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Номер — тот же, что у `Alt-N`: ряд заодно учит клавише.
                      // Дальше девятого номера нет и у клавиши.
                      if (number <= 9) ...[
                        Text('$number', style: theme.statusStyle.copyWith(color: colors.secondaryText)),
                        SizedBox(width: metrics.cellPadding),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: shown ? theme.pathStyle : theme.statusStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              mark(shownRight),
            ],
          ),
        ),
      ),
    );
  }
}
