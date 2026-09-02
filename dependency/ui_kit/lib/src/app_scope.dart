import 'package:flutter/widgets.dart';

import 'package:fc_ui_api/fc_ui_api.dart';

/// Доступ к состоянию приложения из дерева виджетов.
///
/// [InheritedNotifier]: изменения уровня приложения (активная панель, доля
/// разделителя, тема) редки, и перестроить на них зависимые виджеты дешевле,
/// чем разводить подписки вручную.
///
/// Живёт в API, а не в ядре: виджеты модулей — экран панелей, просмотрщик —
/// достают приложение отсюда, а зависеть от ядра модуль не может.
class AppScope extends InheritedNotifier<Application> {
  const AppScope({super.key, required Application controller, required super.child}) : super(notifier: controller);

  static Application of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден выше по дереву');
    return scope!.notifier!;
  }

  /// Приложение без подписки на изменения — для обработчиков событий.
  static Application read(BuildContext context) {
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

  final Panel panel;

  static Panel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PanelScope>();
    assert(scope != null, 'PanelScope не найден выше по дереву');
    return scope!.panel;
  }

  @override
  bool updateShouldNotify(PanelScope oldWidget) => oldWidget.panel != panel;
}
