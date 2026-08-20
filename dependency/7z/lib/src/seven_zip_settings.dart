import 'package:fc_api/fc_api.dart';

/// Что модуль помнит между запусками.
class SevenZipSettings implements Serializable {
  SevenZipSettings({this.binary = ''});

  /// Путь к программе или её имя. Пусто — искать самим.
  ///
  /// Нужно там, где программа лежит не там, где её ищут: своя сборка,
  /// необычный каталог, несколько версий рядом.
  String binary;

  @override
  void fromMap(Map<String, dynamic> m) => binary = extract(binary, m['binary']);

  @override
  void toMap(Map<String, dynamic> m) => m['binary'] = binary;
}
