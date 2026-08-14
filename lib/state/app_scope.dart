import 'package:flutter/widgets.dart';

import 'app_controller.dart';
import 'panel_controller.dart';

/// Доступ к состоянию приложения из дерева виджетов.
///
/// [InheritedNotifier]: изменения уровня приложения (активная панель, доля
/// разделителя, тема) редки, и перестроить на них зависимые виджеты дешевле,
/// чем разводить подписки вручную.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден выше по дереву');
    return scope!.notifier!;
  }

  /// Контроллер без подписки на изменения — для обработчиков событий.
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден выше по дереву');
    return scope!.notifier!;
  }
}

/// Доступ к панели, внутри которой находится виджет.
///
/// Обычный [InheritedWidget], а не [InheritedNotifier]: панель уведомляет и о
/// движении курсора, поэтому на неё подписываются точечно — там, где это
/// действительно нужно, через `ListenableBuilder`.
class PanelScope extends InheritedWidget {
  const PanelScope({super.key, required this.panel, required super.child});

  final PanelController panel;

  static PanelController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PanelScope>();
    assert(scope != null, 'PanelScope не найден выше по дереву');
    return scope!.panel;
  }

  @override
  bool updateShouldNotify(PanelScope oldWidget) => oldWidget.panel != panel;
}
