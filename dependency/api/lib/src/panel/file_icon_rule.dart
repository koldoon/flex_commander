import 'entry_condition.dart';

/// Чем рисовать иконку — как это записано в настройках.
///
/// Значение, а не виджет: `fc_api` не знает ни про шрифты темы, ни про
/// картинки. Роль здесь — имя роли, глиф — код, картинка — путь; во что это
/// превратить, решает тот, кто рисует (`spec/file-icons.md`, §4).
sealed class IconSource {
  const IconSource();

  /// Разбор записи из настроек; null — запись не разобралась.
  ///
  /// Неразобранная запись не роняет приложение и ничего не рисует: правило с
  /// ней пропускается. Файл настроек правят руками, а опечатка в нём не повод
  /// не показать каталог.
  static IconSource? parse(String value) {
    final text = value.trim();
    if (text == 'system') {
      return const SystemIconSource();
    }
    if (text.startsWith('image:')) {
      final path = text.substring('image:'.length).trim();
      return path.isEmpty ? null : PictureSource(path);
    }
    if (text.startsWith('glyph:')) {
      final glyph = text.substring('glyph:'.length).trim();
      if (glyph.isEmpty) {
        return null;
      }
      // Шестнадцатеричное — код глифа, всё остальное — имя роли. Ни одна роль
      // темы не состоит из одних лишь цифр и букв `a`–`f`, поэтому разобрать
      // одно за другое нельзя.
      final code = _hex.hasMatch(glyph) ? int.tryParse(glyph, radix: 16) : null;
      return code == null ? GlyphRoleSource(glyph) : GlyphCodeSource(code);
    }
    return null;
  }

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]{2,6}$');

  /// Запись обратно в настройки — ровно та, из которой разобрали.
  String get text;
}

/// Роль темы: `glyph:folder`. Сменится тема — сменится и глиф.
class GlyphRoleSource extends IconSource {
  const GlyphRoleSource(this.role);

  final String role;

  @override
  String get text => 'glyph:$role';
}

/// Глиф кодом: `glyph:f07b`.
///
/// Привязан к шрифту темы: у другого набора иконок по этому коду может не быть
/// ничего. Роль от этого защищена, код — нет, и это цена свободы выбирать
/// любой глиф шрифта, а не только названный.
class GlyphCodeSource extends IconSource {
  const GlyphCodeSource(this.codePoint);

  final int codePoint;

  @override
  String get text => 'glyph:${codePoint.toRadixString(16)}';
}

/// Картинка с диска: `image:~/.flex-commander/icons/dart.png`.
class PictureSource extends IconSource {
  const PictureSource(this.path);

  /// Путь как записан, вместе с `~`: разворачивает его тот, кто читает файлы.
  final String path;

  @override
  String get text => 'image:$path';
}

/// Значок, который об этом объекте знает система.
class SystemIconSource extends IconSource {
  const SystemIconSource();

  @override
  String get text => 'system';
}

/// Правило: условие → чем рисовать.
///
/// Список правил проверяется по порядку, **первое совпавшее выигрывает**.
/// Складывать иконки нельзя, а порядок — единственное понятное объяснение,
/// почему строка выглядит именно так.
class FileIconRule {
  const FileIconRule({required this.when, required this.icon});

  final EntryCondition when;
  final IconSource icon;

  /// Разбор одного правила; null — правила не вышло, и его пропускают.
  static FileIconRule? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final map = json.cast<String, Object?>();
    final source = map['icon'];
    if (source is! String) {
      return null;
    }
    final icon = IconSource.parse(source);
    return icon == null ? null : FileIconRule(when: EntryCondition.fromJson(map), icon: icon);
  }

  /// Разбор списка правил: непонятные записи выбрасываются молча.
  static List<FileIconRule> listFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return [
      for (final item in json)
        if (fromJson(item) case final rule?) rule,
    ];
  }

  Map<String, Object?> toJson() => {...when.toJson(), 'icon': icon.text};
}
