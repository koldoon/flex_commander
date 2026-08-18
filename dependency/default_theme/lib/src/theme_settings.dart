import 'package:fc_api/fc_api.dart';

/// Что модуль темы помнит между запусками.
class ThemeSettings implements Serializable {
  ThemeSettings({this.themeId = defaultThemeId});

  /// Имя темы, с которой приложение открывается по умолчанию.
  static const String defaultThemeId = 'default';

  /// Выбранная тема. Имя, а не сама тема: модуль, который её приносит, могли
  /// отключить, и тогда останется только имя — с ним ничего не случится.
  String themeId;

  @override
  void fromMap(Map<String, dynamic> m) => themeId = extract(themeId, m['themeId']);

  @override
  void toMap(Map<String, dynamic> m) => m['themeId'] = themeId;
}
