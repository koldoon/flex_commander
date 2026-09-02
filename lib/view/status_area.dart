import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

/// Общее место для работ, ушедших в фон.
///
/// Полоска над нижней панелью: по строке на работу — название, ход дела и
/// крестик. Пока фоновых работ нет, её не видно вовсе: пустая полоса отнимала
/// бы место у панелей.
class StatusArea extends StatelessWidget {
  const StatusArea({super.key, required this.tasks, required this.owner});

  final Operations tasks;

  /// Чьи работы показывать: под какой панелью стоит эта область.
  final ViewportPosition owner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tasks,
      builder: (context, _) {
        final running = tasks.at(owner);
        if (running.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final task in running) _RunRow(task: task, operations: tasks)],
        );
      },
    );
  }
}

/// Одна работа: сколько сделано и чем её остановить.
class _RunRow extends StatelessWidget {
  const _RunRow({required this.task, required this.operations});

  final Operations operations;

  final OperationRun task;

  /// Просит прервать работу — и сразу возвращает ей окно.
  ///
  /// Нажатый крестик и есть внимание человека: он смотрит сюда и уже решил.
  /// Показывать ему после этого кнопку «нужен ответ», чтобы он нажал её ещё
  /// раз ради того же самого вопроса, — лишний шаг на пустом месте.
  ///
  /// Окно возвращается **до** просьбы: прерывание не молчаливое, операция
  /// переспросит на ближайшей проверке, и к этому моменту спрашивать должно
  /// быть уже где.
  void _requestCancel(OperationRun task) {
    operations.bringToFront(task.runId);
    task.operation.requestCancel();
  }

  /// Крестик у **законченной** работы означает «забыть».
  ///
  /// Прерывать там нечего, а полоска может пережить работу: поиск, кончившийся
  /// в фоне, остаётся на виду со своим итогом — результат и есть вся его
  /// работа, и выбросить его молча нельзя. Копирование до сих пор забывало себя
  /// само, и такого состояния попросту не бывало.
  void _forget(OperationRun task) => operations.forget(task.runId);

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return ListenableBuilder(
      listenable: task.status,
      builder: (context, _) {
        final finished = task.status.state.isFinished;

        // Щелчок по самой полоске возвращает окно работы: целятся именно в
        // неё, а не в мелкий знак вопроса рядом. Он же и остаётся — им
        // отвечают на вставший вопрос, и это другое дело.
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => operations.bringToFront(task.runId),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.dialogGap, vertical: metrics.strokeWidth * 2),
              child: Row(
                children: [
                  Text('${task.title}: ', style: theme.statusStyle),
                  Expanded(child: Text(task.status.message, style: theme.statusStyle, overflow: TextOverflow.ellipsis)),
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
                  // каталог, — окна не выдёргивает: человек занят другим. Кнопка
                  // ждёт, пока он сам решит вернуться.
                  if (task.status.state == OperationState.userActionRequired)
                    _AttentionButton(onPressed: () => operations.bringToFront(task.runId), theme: theme),
                  _CancelButton(onPressed: finished ? () => _forget(task) : () => _requestCancel(task), theme: theme),
                ],
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
