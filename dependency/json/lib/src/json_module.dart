import 'package:fc_ui_api/fc_ui_api.dart';

import 'json_format.dart';

/// Форматтер json — первый потребитель реестра из Г3.
///
/// Модуль объявляет **одну** вещь: чем привести json в читаемый вид. Ни команд,
/// ни клавиш, ни своих экранов у него нет. Выключите его — `.json` снова
/// откроется как есть, и это единственное, что изменится
/// (`docs/spec/formatters.md`, §3).
class JsonFormatting implements FcFrontendModule {
  const JsonFormatting();

  @override
  String get id => 'fc.json';

  @override
  String get title => 'JSON';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.formatter(
      FormatterSpec(
        id: 'json',
        title: 'JSON',
        // По имени, а не по типу содержимого: у json нет подписи в первых
        // байтах, и таблица типов его не знает вовсе. Тип здесь приходит ради
        // тех форматов, у которых подпись есть.
        accepts: (entry, type) => entry.name.toLowerCase().endsWith('.json'),
        format: formatJson,
      ),
    );
  }
}

/// Русские строки форматтера.
const Map<String, String> _russian = {'JSON': 'JSON'};
