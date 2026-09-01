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
    final app = AppScope.of(context);

    return ListenableBuilder(
      // И на рабочую область тоже: полос набора на экране бывает две — своя у
      // каждой панели, — а клавиши в любой момент достаются ровно одной.
      listenable: Listenable.merge([state, app.view]),
      builder: (context, _) {
        // Обводка и курсор — только там, куда попадёт следующее нажатие. Вопрос
        // задаётся общий, тот же, которым панель решает, светить ли плашке:
        // считать это самому — верный способ разойтись с соседом.
        //
        // И плюс окна: открытое окно команды забирает клавиши **целиком**, и
        // курсор с обводкой в этот момент стоят в нём. Плашке панели это не
        // мешает — она говорит, чья сторона, а не куда печатать, — а здесь
        // получалось два курсора: в поле окна и под панелью.
        final takesKeys = app.view.takesKeys(state) && app.view.dialogs.isEmpty;

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
                    border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                    borderRadius: BorderRadius.circular(metrics.inputRadius),
                  ),
                  // Обводка фокуса — та же и той же толщины, что у настоящих
                  // полей, и так же **поверх**, а не рамкой: выглядеть это
                  // должно как везде. Своей рамкой она была вдвое тоньше.
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: takesKeys ? colors.focusRing : const Color(0x00000000),
                      width: metrics.focusRingWidth,
                    ),
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
                      // Курсор — общий на всё приложение: та же толщина, те же
                      // скруглённые торцы, то же мигание. Набор его сбрасывает:
                      // пока печатают, курсор виден.
                      //
                      // И его нет вовсе там, где нет клавиш: курсор — это
                      // обещание, что сюда попадёт нажатие, и в полосе под
                      // соседней панелью оно ложное.
                      if (takesKeys)
                        Padding(
                          padding: EdgeInsets.only(left: metrics.strokeWidth),
                          child: FcCaret(style: theme.inputStyle, resetOn: state.pattern),
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
