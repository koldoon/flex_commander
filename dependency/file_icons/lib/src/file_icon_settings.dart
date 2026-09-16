import 'package:fc_api/fc_api.dart';

/// Что иконки помнят между запусками.
class FileIconSettings implements Serializable {
  FileIconSettings({this.size = 0, this.system = false, this.thumbnails = true, List<FileIconRule>? rules})
    : rules = rules ?? const [];

  /// Наибольший размер, который имеет смысл: дальше иконка спорит со строкой.
  static const int maxSize = 32;

  /// Размер иконки в точках; `0` — как в теме.
  ///
  /// Ноль, а не 13: величина темы может смениться вместе с темой, и записанное
  /// однажды число заморозило бы размер навсегда.
  int size;

  /// Спрашивать ли систему о значке для всего, что лежит на диске.
  ///
  /// Один переключатель для самого частого желания — «покажи как в Finder».
  /// Кому нужно тоньше, тот пишет правила: они стоят выше флага.
  bool system;

  /// Показывать ли содержимое файла вместо значка формата.
  ///
  /// **Включено по умолчанию**, в отличие от [system]: значок системы меняет то,
  /// как выглядит привычный список, а миниатюра появляется только там, где её
  /// просили размером, — в сетке значков
  /// (`docs/spec/file-thumbnails.md`, §6).
  bool thumbnails;

  /// Правила: условие → чем рисовать, первое совпавшее выигрывает.
  ///
  /// Окна правки у них нет — список в схему настроек не ложится, — и правятся
  /// они в файле (`docs/spec/file-icons.md`, §10).
  List<FileIconRule> rules;

  @override
  void fromMap(Map<String, dynamic> m) {
    size = extract(size, m['size']);
    system = extract(system, m['system']);
    thumbnails = extract(thumbnails, m['thumbnails']);
    rules = FileIconRule.listFromJson(m['rules']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['size'] = size;
    m['system'] = system;
    m['thumbnails'] = thumbnails;
    m['rules'] = [for (final rule in rules) rule.toJson()];
  }
}
