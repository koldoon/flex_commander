import 'dart:io';

import 'package:fc_api/fc_api.dart';

/// Значение настройки, означающее «как у системы».
const String systemLanguage = 'system';

/// Язык системы — тот, на котором приложение заговорит без выбора.
///
/// Считается один раз: `Platform.localeName` спрашивают на каждую надпись, а
/// меняется он не чаще, чем раз в жизни процесса.
final String machineLanguage = _machine();

/// Какой язык означает эта настройка.
///
/// `system` разрешается **на каждой стороне самостоятельно**: обе стоят на
/// одной машине и получают один ответ, поэтому везти разрешённый язык через
/// границу незачем (`docs/spec/localization.md`, §9).
String languageOf(String setting) {
  if (setting != systemLanguage && StringsRegistry.languages.contains(setting)) {
    return setting;
  }
  return machineLanguage;
}

/// `ru_RU.UTF-8` → `ru`. Незнакомый язык системы — английский: непереведённое
/// приложение честнее наполовину переведённого.
String _machine() {
  final name = Platform.localeName;
  final code = name.split(RegExp('[_.-]')).first.toLowerCase();
  return StringsRegistry.languages.contains(code) ? code : StringsRegistry.defaultLanguage;
}
