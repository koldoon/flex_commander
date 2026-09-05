import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import '../state/background_tasks_state.dart';

/// Список работ, ушедших в фон, — под той панелью, с которой их отправили.
///
/// Спецификация — `docs/spec/background-operations.md`. Обычная область
/// приложения: рама, курсор, клавиши. Пока фоновых работ нет, области нет
/// вовсе — её убирает `BackgroundTasks`.
class BackgroundTasksView extends StatefulWidget {
  const BackgroundTasksView({super.key, required this.state});

  final BackgroundTasksState state;

  /// Сколько строк видно разом. Дальше — прокрутка.
  ///
  /// Четыре, а не «сколько есть»: список стоит под панелью и растёт за её счёт.
  /// Работ обычно единицы, но бывает и десяток — и тогда он не должен съесть
  /// список файлов.
  static const int visibleRows = 4;

  @override
  State<BackgroundTasksView> createState() => _BackgroundTasksViewState();
}

class _BackgroundTasksViewState extends State<BackgroundTasksView> {
  final ScrollController _scroll = ScrollController();

  int _shownCursor = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Держит строку под курсором на виду: перебор стрелками не должен уезжать
  /// за край.
  void _showCursor(double line) {
    if (!_scroll.hasClients) {
      return;
    }
    final top = widget.state.cursor * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      _scroll.jumpTo((top + line - position.viewportDimension).clamp(0, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final app = AppScope.of(context);
    // Шаг строк — тот же, которым размечен список файлов над ним, и берётся он
    // оттуда же: просвет `rowGap` лежит **внутри** шага, а сам шаг растёт
    // вместе с размером иконки. Считай мы его здесь своей формулой — ритм
    // совпадал бы только при размере по умолчанию.
    final line = FileIconSize.listRow(metrics, app.fileIcons);

    return ListenableBuilder(
      // И на рабочую область тоже: курсор горит только там, куда попадёт
      // следующее нажатие, а это состояние живёт в ней.
      listenable: Listenable.merge([widget.state, app.view]),
      builder: (context, _) {
        final runs = widget.state.runs;
        if (runs.isEmpty) {
          // Список без работ не показывается: его убирает сторож, а до того
          // кадра рисовать пустую раму незачем.
          return const SizedBox.shrink();
        }

        final takesKeys = app.view.takesKeys(widget.state) && app.view.dialogs.isEmpty;
        if (widget.state.cursor != _shownCursor) {
          _shownCursor = widget.state.cursor;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showCursor(line));
        }

        final rows = runs.length < BackgroundTasksView.visibleRows ? runs.length : BackgroundTasksView.visibleRows;

        // Высота задаётся **снаружи** рамы: внутри у неё `Expanded`, и без
        // конечной высоты его не разложить — а места под панелью столько,
        // сколько попросишь.
        return SizedBox(
          height: line * rows + 2 * metrics.strokeWidth,
          child: FcPanelFrame(
            // Плашки заголовка нет: под панелью и так понятно, чьи это работы,
            // а лишний заголовок внизу экрана только шумит. Значит и места под
            // неё оставлять не нужно — содержимое занимает раму целиком.
            fillsFrame: true,
            child: ListView.builder(
              controller: _scroll,
              itemExtent: line,
              itemCount: runs.length,
              primary: false,
              itemBuilder: (context, index) {
                final task = runs[index];
                return _RunRow(
                  task: task,
                  operations: widget.state.operations,
                  // Курсор виден там, где клавиши, — то же правило, по которому
                  // меркнет курсор неактивной панели.
                  underCursor: index == widget.state.cursor && takesKeys,
                  onTap: () {
                    widget.state.cursor = index;
                    widget.state.operations.bringToFront(task.runId);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Одна работа: сколько сделано и чем её остановить.
class _RunRow extends StatelessWidget {
  const _RunRow({required this.task, required this.operations, required this.underCursor, required this.onTap});

  final Operations operations;

  final OperationRun task;

  final bool underCursor;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return ListenableBuilder(
      listenable: task.status,
      builder: (context, _) {
        // Щелчок по самой строке возвращает окно работы: целятся именно в неё,
        // а не в мелкий знак вопроса рядом. Он же и остаётся — им отвечают на
        // вставший вопрос, и это другое дело.
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            // Просвет между строками: подсветка курсора не смыкается со
            // следующей — то же правило, что в списке файлов.
            child: Padding(
              padding: EdgeInsets.only(bottom: metrics.rowGap),
              child: DecoratedBox(
                decoration: BoxDecoration(color: underCursor ? theme.colors.cursorBackground : null),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.dialogGap),
                  child: Row(
                    children: [
                      Text('${task.title}: ', style: theme.statusStyle),
                      Expanded(
                        child: Text(task.status.message, style: theme.statusStyle, overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: metrics.dialogGap),
                      SizedBox(
                        width: metrics.dialogLabelWidth / 2,
                        child: FcProgressBar(
                          value:
                              task.status is ComputableOperationStatus
                                  ? (task.status as ComputableOperationStatus).percentProgress
                                  : null,
                        ),
                      ),
                      SizedBox(width: metrics.dialogGap),
                      // Вопрос, возникший сам собой — конфликт имён, недоступный
                      // каталог, — окна не выдёргивает: человек занят другим.
                      // Кнопка ждёт, пока он сам решит вернуться.
                      if (task.status.state == OperationState.userActionRequired)
                        _AttentionButton(onPressed: () => operations.bringToFront(task.runId), theme: theme),
                      _CancelButton(onPressed: () => cancelOrForgetTask(operations, task), theme: theme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed, required this.theme});

  final VoidCallback? onPressed;
  final FcTheme theme;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onPressed == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Opacity(opacity: onPressed == null ? 0.5 : 1, child: Text('✕', style: theme.statusStyle)),
      ),
    );
  }
}

/// Работа встала и ждёт ответа: вернуть ей окно.
///
/// Окно само не выпрыгивает — вырывать человека из другого дела нельзя, а
/// вопрос никуда не денется. Но и молчать нельзя, иначе работа стоит, а он
/// этого не замечает: здесь она об этом и говорит.
class _AttentionButton extends StatelessWidget {
  const _AttentionButton({required this.onPressed, required this.theme});

  final VoidCallback onPressed;
  final FcTheme theme;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.only(right: theme.metrics.dialogGap / 2),
          child: Text('?', style: theme.statusStyle),
        ),
      ),
    );
  }
}

/// Что делает крестик: прервать работу, а у законченной — забыть её.
///
/// Отдельной функцией, потому что то же самое делают `Bsp` и `Del`: одно
/// действие, два способа его позвать — и один текст на оба.
///
/// **Прерывание возвращает окно до просьбы.** Нажатый крестик и есть внимание
/// человека: он смотрит сюда и уже решил, и показывать ему после этого кнопку
/// «нужен ответ» ради того же вопроса — лишний шаг на пустом месте. А
/// прерывание не молчаливое: работа переспросит на ближайшей проверке, и к
/// этой минуте спрашивать должно быть уже где.
///
/// **У законченной работы это «забыть».** Прерывать там нечего, а строка может
/// пережить работу: поиск, кончившийся в фоне, остаётся со своим итогом —
/// результат и есть вся его работа, и выбросить его молча нельзя.
void cancelOrForgetTask(Operations operations, OperationRun task) {
  if (task.status.state.isFinished) {
    operations.forget(task.runId);
    return;
  }
  operations.bringToFront(task.runId);
  task.operation.requestCancel();
}
