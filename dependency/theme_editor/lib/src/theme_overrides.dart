import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Правки одной темы: чья это накладка и что в ней поправлено.
///
/// Одним и тем же и правки поверх встроенной темы, и своя тема человека:
/// различает их только имя. Пусто — это накладка на встроенную, и `id` у неё
/// тот же, что у неё; названа — это своя тема, и в списке оформления она стоит
/// рядом со встроенными (`docs/spec/theme-editor.md`, §6).
class ThemeEdit {
  ThemeEdit({required this.id, required this.base, this.title = ''});

  /// Имя темы в настройках и в службе оформления.
  final String id;

  /// Поверх какой темы это лежит.
  String base;

  /// Название своей темы; пусто — это правки встроенной.
  String title;

  /// Своя тема, а не правки встроенной.
  bool get isOwn => title.isNotEmpty;

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

  /// Забыть все правки; имя и база остаются — своя тема не исчезает оттого, что
  /// её вернули к базовой.
  void clear() {
    colors.clear();
    metrics.clear();
    uiFont = null;
    fixedFont = null;
    fallback = null;
  }

  /// Скопировать правки в новую тему.
  ThemeEdit copyAs({required String id, required String title}) {
    final copy = ThemeEdit(id: id, base: base, title: title);
    copy.colors.addAll(colors);
    copy.metrics.addAll(metrics);
    copy.uiFont = uiFont;
    copy.fixedFont = fixedFont;
    copy.fallback = fallback == null ? null : [...fallback!];
    return copy;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'base': base,
    if (title.isNotEmpty) 'title': title,
    'colors': {for (final entry in colors.entries) entry.key: formatColor(entry.value)},
    'metrics': {...metrics},
    'fonts': {
      if (uiFont case final font?) 'ui': font,
      if (fixedFont case final font?) 'fixed': font,
      if (fallback case final list?) 'fixedFallback': list,
    },
  };

  /// Испорченное значение заменяется умолчанием, а не роняет разбор (сквозное
  /// правило 5): роль, которой в контракте нет, и цвет, который не разобрался,
  /// просто пропускаются. Записи без имени темы нет вовсе.
  static ThemeEdit? fromJson(Object? stored) {
    if (stored is! Map<String, dynamic>) {
      return null;
    }
    final id = stored['id'];
    final base = stored['base'];
    if (id is! String || id.isEmpty || base is! String || base.isEmpty) {
      return null;
    }

    final edit = ThemeEdit(id: id, base: base, title: stored['title'] is String ? stored['title'] as String : '');

    if (stored['colors'] case final Map<String, dynamic> colors) {
      for (final entry in colors.entries) {
        if (entry.value case final String text) {
          if (parseColor(text) case final color?) {
            edit.colors[entry.key] = color;
          }
        }
      }
    }
    if (stored['metrics'] case final Map<String, dynamic> metrics) {
      for (final entry in metrics.entries) {
        if (entry.value case final num value) {
          edit.metrics[entry.key] = value.toDouble();
        }
      }
    }
    if (stored['fonts'] case final Map<String, dynamic> fonts) {
      edit.uiFont = fonts['ui'] is String ? fonts['ui'] as String : null;
      edit.fixedFont = fonts['fixed'] is String ? fonts['fixed'] as String : null;
      edit.fallback =
          fonts['fixedFallback'] is List
              ? [
                for (final item in fonts['fixedFallback'] as List)
                  if (item is String) item,
              ]
              : null;
    }
    return edit;
  }
}

/// Что редактор тем помнит между запусками.
///
/// Обычным разделом обычного файла настроек (`fc.theme_editor`), а не своим
/// форматом: отдельный файл означал бы второй разбор и второй способ
/// испортиться (`docs/spec/theme-editor.md`, §6).
class ThemeOverrides implements Serializable {
  /// Правки встроенных тем и свои темы человека — одним списком.
  final List<ThemeEdit> themes = [];

  /// Правки этой темы; null — их нет.
  ThemeEdit? find(String id) => themes.where((edit) => edit.id == id).firstOrNull;

  /// Свои темы человека — в том порядке, в каком он их складывал.
  List<ThemeEdit> get own => [
    for (final edit in themes)
      if (edit.isOwn) edit,
  ];

  /// Правки этой темы, заведя их, если их ещё нет.
  ThemeEdit edit(String id, {required String base}) {
    if (find(id) case final existing?) {
      return existing;
    }
    final fresh = ThemeEdit(id: id, base: base);
    themes.add(fresh);
    return fresh;
  }

  void add(ThemeEdit edit) => themes.add(edit);

  void remove(String id) => themes.removeWhere((edit) => edit.id == id);

  @override
  void fromMap(Map<String, dynamic> m) {
    themes.clear();
    if (m['themes'] case final List stored) {
      for (final item in stored) {
        if (ThemeEdit.fromJson(item) case final edit?) {
          themes.add(edit);
        }
      }
    }
  }

  @override
  void toMap(Map<String, dynamic> m) {
    // Пустые правки не пишутся, а своя тема пишется всегда: тема без правок —
    // это всё ещё тема, и пропасть из списка она не должна.
    m['themes'] = [
      for (final edit in themes)
        if (edit.isOwn || !edit.isEmpty) edit.toJson(),
    ];
  }
}
