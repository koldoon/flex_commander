import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import '../state/commands/session_commands.dart';

/// Ряд открытых наборов — **один общий на всё окно**, в полосе заголовка
/// (`docs/spec/panel-sessions.md`, §3).
///
/// Рисует его шелл, а не модуль панелей: набор не принадлежит стороне, и ряд
/// на каждую сторону врал бы об этом устройстве — как и вопрос «а в чей ряд
/// попал заведённый набор».
///
/// **Виден всегда**, даже когда оба набора показаны: в полосе заголовка он ни
/// у кого не отнимает места — полоса есть в окне всегда и до сих пор пустовала
/// (`docs/spec/window-chrome.md`, §3). Прижат к правому краю, а слева
/// останавливается там, где кончается свободная ручка окна: место под ряд
/// отмеряет полоса, а не он сам.
class PanelRow extends StatelessWidget {
  const PanelRow({super.key});

  /// Ключи горящих ячеек метки: по ним проверка узнаёт, где набор показан.
  static const Key leftMarkKey = Key('panel-row-mark-left');
  static const Key rightMarkKey = Key('panel-row-mark-right');

  /// Ключ кнопки «завести набор» — последней в ряду.
  static const Key newPanelKey = Key('panel-row-new');

  /// Ключ записи по её номеру — тому же, что виден в ряду.
  static Key chipKey(int number) => ValueKey('panel-row-chip-$number');

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
        return ListenableBuilder(
          listenable: Listenable.merge([for (final panel in panels) panel.session]),
          builder: (context, _) => _row(context, app, panels, left, right),
        );
      },
    );
  }

  Widget _row(BuildContext context, Application app, List<Panel> panels, Panel left, Panel right) {
    final metrics = FcTheme.of(context).metrics;
    return Center(
      // Ростом записи облегают свой текст, а по вертикали ряд стоит **по
      // центру полосы** — там же, где светофор.
      child: Row(
        // Справа налево: у правого края ряд стоит там же, где кончаются
        // панели, а прибывающие наборы растут внутрь окна, не сдвигая
        // остальных с насиженных мест.
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var at = 0; at < panels.length; at++) ...[
            // Дистанция между записями — та же, что между областями окна:
            // другой величине здесь взяться неоткуда.
            if (at > 0) SizedBox(width: metrics.areaGap),
            // По содержимому: запись занимает столько, сколько нужно имени.
            // Тесно — ужимается по очереди, а не делит ширину поровну.
            Flexible(
              child: _PanelChip(
                key: PanelRow.chipKey(at + 1),
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
          SizedBox(width: metrics.areaGap),
          // Кнопка нового набора — последней, как вкладка «плюс» в браузере.
          // Не `Flexible`: ужимаются имена, а кнопка держит свой размер —
          // завести набор должно быть можно и в тесном окне.
          _NewPanelButton(onTap: () => app.commands.run(NewSessionCommand.commandId)),
        ],
      ),
    );
  }
}

/// Кнопка «завести набор»: рамка записи, а внутри — знак «плюс».
class _NewPanelButton extends StatelessWidget {
  const _NewPanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    return Tooltip(
      message: context.strings.tr('New session'),
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        key: PanelRow.newPanelKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding),
          decoration: BoxDecoration(
            color: colors.panelBackground,
            border: Border.all(color: colors.panelBorder, width: metrics.strokeWidth),
            borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
          ),
          // Знак набран **тем же шрифтом**, что имена в записях, только
          // жирным: иконочный глиф здесь ни к чему — плюс есть в любом наборе.
          // Заодно кнопка меряется той же строкой, что и записи, и выходит
          // ровно их роста.
          child: Text('+', style: theme.statusStyle.copyWith(fontWeight: FontWeight.bold, color: colors.secondaryText)),
        ),
      ),
    );
  }
}

/// Один набор в ряду: номер, имя и метка того, где он показан.
///
/// Метка — **мини-пара панелей у правой границы**: две ячейки, левая горит,
/// когда набор показан слева, правая — когда справа, обе — когда в обеих.
/// Буквами это пришлось бы читать, а пара сама похожа на то, что показывает.
/// Место у неё всегда одно, поэтому она читается как метка записи, а не как
/// значок перед именем.
class _PanelChip extends StatelessWidget {
  const _PanelChip({
    super.key,
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

    // Погасшая ячейка не пропадает, а темнеет: пара читается как две панели, и
    // одна ячейка вместо двух означала бы другое. Высота — со строчную букву:
    // метка стоит в строке, а не подпирает её края.
    Widget cell(bool lit, Key key) => SizedBox(
      width: metrics.markedBarWidth,
      height: metrics.iconSize,
      child: ColoredBox(color: lit ? colors.markedBar : colors.panelBorder, key: lit ? key : null),
    );

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
          // Поля как у плашки пути, и только по горизонтали: высоту записи
          // держит сам ряд, а вертикальные поля отняли бы её у текста.
          padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding),
          decoration: BoxDecoration(
            color: shown ? colors.pathBackground : colors.panelBackground,
            border: Border.all(color: shown ? colors.pathBorder : colors.panelBorder, width: metrics.strokeWidth),
            borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
          ),
          // По содержимому: запись занимает столько, сколько нужно её имени.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Номер — тот же, что у `Alt-N`: ряд заодно учит клавише. Дальше
              // девятого номера нет и у клавиши.
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
              // Непоказанный ничем не помечен: пустое место говорит само.
              if (shown) ...[
                SizedBox(width: metrics.cellPadding * 2),
                cell(shownLeft, PanelRow.leftMarkKey),
                SizedBox(width: metrics.strokeWidth),
                cell(shownRight, PanelRow.rightMarkKey),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
