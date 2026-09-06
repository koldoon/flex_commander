import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
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

/// Строки на языке человека — для дерева виджетов.
///
/// Свой [InheritedNotifier], а не поле приложения: язык меняется отдельно от
/// состояния, и подписаться на него должны ровно те виджеты, которые показывают
/// надписи. Ставится над `MaterialApp`, поэтому его видят и окна: они живут в
/// накладке под ним.
///
/// Области нет вовсе — значит английский, тот же, что написан в коде: так
/// проверке отдельного виджета не приходится поднимать приложение целиком
/// (`docs/spec/localization.md`).
class StringsScope extends InheritedNotifier<Strings> {
  const StringsScope({super.key, required Strings strings, required super.child}) : super(notifier: strings);

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()?.notifier ?? _plain;

  static final Strings _plain = StringsRegistry();
}

/// Строки там, где есть дерево виджетов: `context.strings.tr('Search')`.
extension FcStrings on BuildContext {
  Strings get strings => StringsScope.of(this);
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
