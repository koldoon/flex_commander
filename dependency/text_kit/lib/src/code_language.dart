import 'package:re_highlight/languages/all.dart';

/// Язык подсветки по имени файла; null — подсвечивать нечем.
///
/// Отдельно от просмотрщика нарочно: тащить зависимость на соседний модуль
/// ради одной таблицы — плохой обмен. Когда просмотрщик и редактор съедутся на
/// один виджет, съедется и она.
String? languageOf(String fileName) {
  final name = fileName.toLowerCase();
  final byName = _byFileName[name];
  if (byName != null) {
    return byName;
  }

  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return null;
  }
  return languageNamed(name.substring(dot + 1));
}

/// Язык подсветки по его имени; null — такого нет.
///
/// Тем же столом, что и [languageOf]: врезка ```` ```js ```` в markdown и файл
/// `x.js` должны подсвечиваться одинаково, а две таблицы однажды разойдутся.
String? languageNamed(String name) {
  final language = name.toLowerCase();

  return _byExtension[language] ?? (builtinAllLanguages.containsKey(language) ? language : null);
}

const Map<String, String> _byFileName = {'makefile': 'makefile', 'dockerfile': 'dockerfile', 'cmakelists.txt': 'cmake'};

const Map<String, String> _byExtension = {
  'yml': 'yaml',
  'js': 'javascript',
  'mjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rb': 'ruby',
  'sh': 'bash',
  'zsh': 'bash',
  'h': 'cpp',
  'hpp': 'cpp',
  'cc': 'cpp',
  'cs': 'csharp',
  'kt': 'kotlin',
  'rs': 'rust',
  'md': 'markdown',
  'html': 'xml',
  'htm': 'xml',
  'svg': 'xml',
  'toml': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'ps1': 'powershell',
  'pl': 'perl',
  'tex': 'latex',
  'patch': 'diff',
};
