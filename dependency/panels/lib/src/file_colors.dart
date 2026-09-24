import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Цвет строки по правилам: условие → цвет, первое совпавшее выигрывает
/// (`docs/spec/file-colors.md`).
///
/// Значением, а не службой в реестре: правила лежат в разделе модуля панелей, и
/// спрашивают их те же виды, что этот раздел уже держат в руках. Заводить ради
/// этого объявленную службу значило бы дать её и тем, кто о панелях не знает.
class FileColors {
  const FileColors({required this.rules, this.types});

  /// Правила в том порядке, в каком их проверяют.
  final List<FileColorRule> rules;

  /// Типы по содержимому; null — модуль типов не собран.
  ///
  /// Спрашивается только **известное** (`known`): читать файл ради цвета
  /// нельзя — прокрутка каталога на сто тысяч записей начала бы сто тысяч
  /// чтений (§2б спеки).
  final ContentTypes? types;

  /// Каким цветом писать эту строку; null — обычным.
  Color? of(FileEntry entry, FcColors colors) {
    // «..» — не файл, а выход наверх, и красить его нечем: имя у него чужое
    // (правило про скрытое совпало бы на нём всегда — точка в начале), а
    // признаки не его. Так же его обходит и показ размеров и дат.
    if (rules.isEmpty || entry.isParent) {
      return null;
    }
    // Тип спрашивается **один раз на строку**, а не на каждое правило: ответ
    // один и тот же, а правил бывает десяток.
    ContentType? type;
    var asked = false;

    for (final rule in rules) {
      if (rule.when.needsContent && !asked) {
        type = types?.known(entry);
        asked = true;
      }
      if (rule.when.matches(entry, type: type?.id, group: type?.group.name)) {
        final color = colorOf(rule.color, colors);
        if (color != null) {
          return color;
        }
        // Роли с таким именем в теме нет: правило ничего не красит, и проверка
        // идёт дальше — молча покрасить «чем-нибудь» было бы хуже.
      }
    }
    return null;
  }

  /// Цвет по записи правила: роль темы или число.
  ///
  /// Ролей немного, и они названы списком: полный каталог темы — семь десятков,
  /// и почти весь он про рамы, поля ввода и терминал. Красить имя файла «цветом
  /// границы окна» незачем, а второй каталог рядом с настоящим пришлось бы
  /// держать в согласии руками (§3 спеки). Здесь — роли **текста списка**, те
  /// самые, которыми строка и так бывает написана.
  static Color? colorOf(String value, FcColors colors) {
    if (value.startsWith('#')) {
      final digits = value.substring(1);
      final number = int.tryParse(digits, radix: 16);
      if (number == null) {
        return null;
      }
      // Шесть знаков — цвет без прозрачности: непрозрачность дописываем сами,
      // иначе `#8a8a8a` вышел бы полностью прозрачным.
      return Color(digits.length == 6 ? 0xFF000000 | number : number);
    }
    return switch (value) {
      'rowText' => colors.rowText,
      'secondaryText' => colors.secondaryText,
      'error' => colors.error,
      'pathText' => colors.pathText,
      'cursorText' => colors.cursorText,
      _ => null,
    };
  }
}
