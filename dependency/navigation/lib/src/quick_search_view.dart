import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'quick_search_state.dart';

/// Полоса быстрого поиска под панелью.
///
/// Поле ввода настоящей высоты — той же, что поля в окнах: пока идёт поиск,
/// клавиши принадлежат ему, и это должно быть видно. Курсор в поле — чтобы ввод
/// не приходилось угадывать по рамке.
///
/// Поле при этом **не настоящее**: клавиши разбирает приложение, а не текстовое
/// поле системы. Настоящее пришлось бы фокусировать, отбирая фокус у панели, —
/// а курсор обязан остаться на своём месте в списке.
class QuickSearchView extends StatelessWidget {
  const QuickSearchView({super.key, required this.state});

  final QuickSearchState state;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Padding(
          // Поля те же, что у соседей по этой области: по бокам — как у полосы
          // хода работы (она стоит тут же, под той же панелью), сверху и снизу —
          // как воздух вокруг командной строки: там такое же поле ввода в
          // полосе, и отбито оно должно быть так же.
          padding: EdgeInsets.symmetric(horizontal: metrics.dialogGap, vertical: metrics.commandLineGap),
          child: Row(
            children: [
              Text('Search', style: theme.statusStyle.copyWith(color: colors.secondaryText)),
              SizedBox(width: metrics.columnGap),
              Expanded(
                child: Container(
                  height: metrics.inputHeight,
                  padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: colors.inputBackground,
                    border: Border.all(color: colors.focusRing, width: metrics.strokeWidth),
                    borderRadius: BorderRadius.circular(metrics.inputRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          state.pattern,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.inputStyle,
                        ),
                      ),
                      // Курсор не мигает нарочно: мигание — бесконечная
                      // анимация, и `pumpAndSettle` в тестах не дождался бы её
                      // никогда.
                      Padding(
                        padding: EdgeInsets.only(left: metrics.strokeWidth),
                        child: SizedBox(
                          // Вдвое толще линии: волосяной курсор на общем фоне
                          // не виден, а толще — уже похож на знак.
                          width: metrics.strokeWidth * 2,
                          height: metrics.fontSize,
                          child: ColoredBox(color: colors.inputText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: metrics.columnGap),
              // Выход только по `Esc` — и об этом сказано прямо: пока поле на
              // экране, клавиши не вернутся к панели сами.
              Text('Esc to leave', style: theme.statusStyle.copyWith(color: colors.secondaryText)),
            ],
          ),
        );
      },
    );
  }
}
