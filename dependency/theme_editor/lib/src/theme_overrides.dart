import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Что редактор тем помнит между запусками: чья это накладка и что в ней
/// поправлено.
///
/// Обычным разделом обычного файла настроек (`fc.theme_editor`), а не своим
/// форматом: отдельный файл означал бы второй разбор и второй способ
/// испортиться (`docs/spec/theme-editor.md`, §6).
class ThemeOverrides implements Serializable {
  ThemeOverrides({this.baseThemeId = ''});

  /// Имя темы, к которой подобрана накладка; пусто — накладки нет вовсе.
  ///
  /// Накладка сделана **для своей темы**: цвета, подобранные к тёмной, светлую
  /// испортят. Сменили тему — накладка не применяется; вернулись — легла снова.
  String baseThemeId;

  /// Роль → цвет.
  final Map<String, Color> colors = {};

  /// Роль → размер.
  final Map<String, double> metrics = {};

  /// Шрифт интерфейса; null — берётся у темы. Пустая строка — тоже своё: «тот,
  /// что выберет система».
  String? uiFont;

  /// Шрифт списка файлов; null — берётся у темы.
  String? fixedFont;

  /// Запасные шрифты списка; null — берутся у темы.
  List<String>? fallback;

  /// Нечего применять: тема останется такой, какой её объявил модуль.
  bool get isEmpty => colors.isEmpty && metrics.isEmpty && uiFont == null && fixedFont == null && fallback == null;

  /// Сколько ролей поправлено — это число и говорит «Reset all».
  int get length => colors.length + metrics.length + [uiFont, fixedFont, fallback].nonNulls.length;

  /// Забыть всё.
  void clear() {
    colors.clear();
    metrics.clear();
    uiFont = null;
    fixedFont = null;
    fallback = null;
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    baseThemeId = extract(baseThemeId, m['baseThemeId']);

    // Испорченное значение заменяется умолчанием, а не роняет разбор (сквозное
    // правило 5): роль, которой в контракте нет, и цвет, который не
    // разобрался, просто пропускаются.
    colors.clear();
    if (m['colors'] case final Map<String, dynamic> stored) {
      for (final entry in stored.entries) {
        if (entry.value case final String text) {
          if (parseColor(text) case final color?) {
            colors[entry.key] = color;
          }
        }
      }
    }

    metrics.clear();
    if (m['metrics'] case final Map<String, dynamic> stored) {
      for (final entry in stored.entries) {
        if (entry.value case final num value) {
          metrics[entry.key] = value.toDouble();
        }
      }
    }

    final fonts = m['fonts'];
    uiFont = fonts is Map<String, dynamic> && fonts['ui'] is String ? fonts['ui'] as String : null;
    fixedFont = fonts is Map<String, dynamic> && fonts['fixed'] is String ? fonts['fixed'] as String : null;
    fallback =
        fonts is Map<String, dynamic> && fonts['fixedFallback'] is List
            ? [
              for (final item in fonts['fixedFallback'] as List)
                if (item is String) item,
            ]
            : null;
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['baseThemeId'] = baseThemeId;
    m['colors'] = {for (final entry in colors.entries) entry.key: formatColor(entry.value)};
    m['metrics'] = {...metrics};
    m['fonts'] = {
      if (uiFont case final font?) 'ui': font,
      if (fixedFont case final font?) 'fixed': font,
      if (fallback case final list?) 'fixedFallback': list,
    };
  }
}
