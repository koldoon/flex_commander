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
          // Только по бокам, и это внутренний отступ содержимого — как у полосы
          // хода работы: она стоит тут же, под той же панелью. Сверху и снизу
          // полоса не отмеряет ничего: зазоры до соседей ставит шелл
          // (`spec/layout-gaps.md`), и полосе незачем знать, кто над ней и кто
          // под ней.
          padding: EdgeInsets.symmetric(horizontal: metrics.dialogGap),
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
                      // Найденное — обычным текстом, ненайденное — выделением.
                      //
                      // Тем же красным, каким выделяют текст в настоящих полях
                      // (`inputSelection`): это и есть выделение, только ставит
                      // его не человек, а поиск — «вот отсюда ничего нет».
                      // Стирается такой кусок тоже как выделенный: одним `Bsp`
                      // целиком.
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: state.matched),
                              if (state.tail.isNotEmpty)
                                TextSpan(text: state.tail, style: TextStyle(backgroundColor: colors.inputSelection)),
                            ],
                          ),
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
