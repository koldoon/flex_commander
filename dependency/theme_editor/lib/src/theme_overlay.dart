import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

import 'overlay_colors.dart';
import 'overlay_fonts.dart';
import 'overlay_metrics.dart';
import 'theme_overrides.dart';

/// Накладка поверх темы: правки живут здесь, а приложение перекрашивается
/// обычной подменой темы (`docs/spec/theme-editor.md`, §5).
///
/// Своего пути до экрана у редактора нет: `ThemeService.register` с тем же
/// `id` заменяет прежнюю тему — это в контракте с самого начала.
class ThemeOverlay {
  ThemeOverlay({required this.themes, required this.overrides, required this.save});

  final ThemeService themes;
  final ThemeOverrides overrides;

  /// Как попросить сохранить раздел настроек.
  final void Function() save;

  /// Тема без правок — та, на которую всё кладётся.
  ///
  /// **Помнится до первой подстановки.** Зарегистрировав накладку под именем
  /// базовой темы, редактор вытесняет базу из списка службы — и вторую правку
  /// класть было бы не на что. Иначе накладки складывались бы стопкой, а
  /// «Reset» одной роли возвращал бы не умолчание, а предыдущую правку.
  FcThemeSpec? _base;

  /// Что мы сами положили в службу — по нему своё уведомление отличается от
  /// чужого.
  FcThemeSpec? _applied;

  /// Чья тема правится сейчас; пусто — правок нет вовсе.
  String get baseThemeId => overrides.baseThemeId;

  FcThemeSpec? get base => _base;

  /// Начать следить за оформлением и положить накладку, если ей есть куда лечь.
  void start() {
    themes.addListener(_themeChanged);
    apply();
  }

  void stop() => themes.removeListener(_themeChanged);

  /// Значение роли **до** правок: с ним форма сравнивает нынешнее, решая,
  /// тронута ли настройка.
  FcThemeSpec get pristine => _base ?? themes.current;

  /// Поправить цвет; null — забыть правку этой роли.
  void setColor(String role, Color? value) => _edit(() => _put(overrides.colors, role, value));

  /// Поправить размер; null — забыть правку.
  void setMetric(String role, double? value) => _edit(() => _put(overrides.metrics, role, value));

  void setUiFont(String? value) => _edit(() => overrides.uiFont = value);

  void setFixedFont(String? value) => _edit(() => overrides.fixedFont = value);

  void setFallback(List<String>? value) => _edit(() => overrides.fallback = value);

  /// Забыть все правки; возвращает, сколько их было.
  int resetAll() {
    final count = overrides.length;
    if (count == 0) {
      return 0;
    }
    overrides.clear();
    save();
    apply();
    return count;
  }

  /// Собрать накладку и объявить её под именем базовой темы.
  ///
  /// Пусто — в службу возвращается сама тема: накладка, из которой убрали всё,
  /// не должна оставаться прослойкой.
  void apply() {
    final base = _base ??= themes.available.where((theme) => theme.id == overrides.baseThemeId).firstOrNull;
    if (base == null) {
      // Темы с таким именем нет: её модуль могли отключить между запусками.
      // Правки при этом целы и ждут (§6).
      return;
    }

    final spec =
        overrides.isEmpty
            ? base
            : FcThemeSpec(
              id: base.id,
              title: base.title,
              brightness: base.brightness,
              colors: OverlayColors(base.colors, overrides.colors),
              metrics: OverlayMetrics(base.metrics, overrides.metrics),
              // Глифы иконок не правятся: это кодовые точки шрифта, и
              // перебирать их вслепую человеку не по чему (§12).
              icons: base.icons,
              fonts: OverlayFonts(
                base.fonts,
                uiFont: overrides.uiFont,
                fixedFont: overrides.fixedFont,
                fallback: overrides.fallback,
              ),
            );

    _applied = spec;
    _applying = true;
    themes.register(spec);
    _applying = false;
  }

  bool _applying = false;

  /// Правка: тронули роль — значит, правим **ту тему, что на экране**.
  ///
  /// Накладка одна и сделана для своей темы (§6). Правка на другой теме
  /// накладку не переносит, а начинает новую: складывать цвета, подобранные к
  /// тёмной, с размерами, подобранными к светлой, было бы хуже, чем начать
  /// заново, — а список своих тем этим этапом не заводится (§12).
  void _edit(void Function() change) {
    final current = themes.current.id;
    if (overrides.baseThemeId != current) {
      // Прежней теме возвращается её собственный вид: наша накладка лежит в
      // службе под её именем, и оставить её там значило бы показывать правки,
      // которых в настройках уже нет, — до первого перезапуска.
      _restoreBase();
      overrides.clear();
      overrides.baseThemeId = current;
      _base = themes.available.where((theme) => theme.id == current).firstOrNull;
    }
    change();
    save();
    apply();
  }

  /// Вернуть в службу ту тему, поверх которой лежала накладка.
  void _restoreBase() {
    final base = _base;
    if (base == null || _applied == null || identical(_applied, base)) {
      return;
    }
    _applying = true;
    themes.register(base);
    _applying = false;
    _applied = base;
  }

  void _put<T>(Map<String, T> where, String role, T? value) {
    if (value == null) {
      where.remove(role);
    } else {
      where[role] = value;
    }
  }

  /// Тему сменили или перевыложили — и это могло быть не нами.
  ///
  /// Признак «это наша накладка» обязан быть: подстановка сама будит этот же
  /// слушатель, и без него первая же правка ушла бы в вечный круг (§5).
  void _themeChanged() {
    if (_applying) {
      return;
    }
    final spec = themes.available.where((theme) => theme.id == overrides.baseThemeId).firstOrNull;
    if (spec == null || identical(spec, _applied) || identical(spec, _base)) {
      return;
    }
    // Тему перевыложил её модуль: класть накладку надо на свежую базу, а не на
    // ту, что запомнили в прошлый раз.
    _base = spec;
    apply();
  }
}
