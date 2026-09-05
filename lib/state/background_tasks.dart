import 'package:fc_ui_api/fc_ui_api.dart';

import 'background_tasks_state.dart';

/// Держит список фоновых работ в статусной области — ровно тогда, когда работы
/// есть.
///
/// Появилась первая работа под панелью — список встал в её статусную область;
/// забыли последнюю — ушёл. Пустой рамы под панелью не бывает: она отнимала бы
/// место у списка файлов, ничего не показывая.
///
/// Отдельным сторожем, а не заботой реестра работ: реестр знает про работы, а
/// про области и стопки — нет, и знать не должен
/// (`docs/spec/background-operations.md`, §4).
class BackgroundTasks {
  BackgroundTasks(this._app) {
    _app.operations.addListener(sync);
    sync();
  }

  final Application _app;

  /// Что сейчас стоит в каждой из статусных областей.
  final Map<ViewportPosition, BackgroundTasksState> _shown = {};

  /// Свести показанное с тем, что есть в реестре.
  void sync() {
    for (final panel in const [ViewportPosition.left, ViewportPosition.right]) {
      final position = panel.status;
      if (position == null) {
        continue;
      }

      final wanted = _app.operations.at(panel).isNotEmpty;
      final shown = _shown[panel];
      if (wanted == (shown != null)) {
        continue;
      }

      if (wanted) {
        final state = BackgroundTasksState(owner: panel, operations: _app.operations);
        _shown[panel] = state;
        _app.view.pushViewportContent(position, state);
      } else {
        _shown.remove(panel);
        // Именно его, а не верхнее: поверх могла лечь полоса быстрого поиска, и
        // убирать просили не её.
        _app.view.removeViewportContent(position, shown!);
      }
    }
  }
}
