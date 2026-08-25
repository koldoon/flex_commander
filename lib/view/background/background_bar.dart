import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

/// Общее место для работ, ушедших в фон.
///
/// Полоска над нижней панелью: по строке на работу — название, ход дела и
/// крестик. Пока фоновых работ нет, её не видно вовсе: пустая полоса отнимала
/// бы место у панелей.
class BackgroundBar extends StatelessWidget {
  const BackgroundBar({super.key, required this.tasks});

  final Operations tasks;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tasks,
      builder: (context, _) {
        final running = [
          for (final run in tasks.all)
            if (run.isInBackground) run,
        ];
        if (running.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final task in running) _BackgroundTaskRow(task: task)],
        );
      },
    );
  }
}

/// Одна фоновая работа: сколько сделано и чем её остановить.
class _BackgroundTaskRow extends StatelessWidget {
  const _BackgroundTaskRow({required this.task});

  final OperationRun task;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return ListenableBuilder(
      listenable: task.status,
      builder: (context, _) {
        return Padding(
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
              // Работа в фоне остаётся управляемой: прервать её можно, не
              // возвращая окна.
              _CancelButton(
                onPressed: task.status.state.isFinished ? null : task.operation.requestCancel,
                theme: theme,
              ),
            ],
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
