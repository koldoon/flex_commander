import 'package:flutter/widgets.dart';

import 'panel.dart';

/// Вид панели: чем показать каталог.
///
/// Спецификация — `docs/spec/panel-views.md`.
///
/// **Не то же, что `PanelViewports`**: там речь о том, **что** в панели —
/// каталог, находки, просмотрщик, — и решает это источник. Здесь о том, **как**
/// показан каталог, и решает это человек (§3).
///
/// Значение, а не служба: объявить вид — не значит распорядиться. Что из
/// объявленного показывать, решает панель по своей настройке.
class PanelViewSpec {
  const PanelViewSpec({
    required this.id,
    required this.title,
    required this.build,
    this.description = '',
    this.options,
  });

  /// Устойчивое имя для настроек: `table`, `brief`, `tree`.
  final String id;

  /// Название для человека — английское, оно же ключ перевода
  /// (`docs/spec/localization.md`, §3).
  final String title;

  /// Одна строка о том, чем этот вид отличается: её читают в окне выбора.
  final String description;

  /// Чем рисовать. Тот же вид работает в любой панели: какая именно — сказано
  /// доводом.
  final Widget Function(BuildContext context, Panel panel) build;

  /// Настройки **этого** вида — их показывает окно выбора под списком: сколько
  /// колонок, какого размера значки, показывать ли миниатюры.
  ///
  /// null — настраивать нечего, и места под них окно не отводит. Правит виджет
  /// раздел своего модуля напрямую: настройки вида общие на приложение, а не
  /// на панель (`docs/spec/panel-views.md`, §7).
  final Widget Function(BuildContext context)? options;
}

/// Виды панели, объявленные модулями.
abstract interface class PanelViews {
  /// Все объявленные виды в порядке объявления модулей.
  List<PanelViewSpec> get available;

  /// Вид по имени; null — такого не объявлял никто.
  ///
  /// Панель на этом не спотыкается: не нашла — рисует таблицей, а имя из
  /// настроек не стирает (`docs/spec/panel-views.md`, §6).
  PanelViewSpec? byId(String id);
}
