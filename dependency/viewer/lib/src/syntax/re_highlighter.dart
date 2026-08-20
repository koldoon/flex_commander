import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'syntax_highlighter.dart';

/// Подсветка поверх `re_highlight` — переноса highlight.js на Dart.
///
/// Разбирается **весь** текст сразу: начало многострочного комментария в одной
/// строке, конец в другой, и построчный разбор их не свяжет. Для файла в
/// пределах ста килобайт это дёшево, а больше просмотрщик и не открывает.
///
/// Полученное дерево спанов режется по переводам строк — показ рисует по
/// строке за раз и о дереве ничего не знает.
class ReHighlighter implements SyntaxHighlighter {
  ReHighlighter(this.colors);

  /// Цвета берутся у оформления приложения, а не у тем библиотеки: как
  /// выглядит приложение, решает тема, а не то, чем разобран синтаксис.
  final FcColors colors;

  final Highlight _highlight = Highlight();
  bool _registered = false;

  @override
  List<TextSpan> highlight(List<String> lines, {required String fileName, required TextStyle base}) {
    final language = languageOf(fileName);
    if (language == null) {
      return const PlainHighlighter().highlight(lines, fileName: fileName, base: base);
    }

    if (!_registered) {
      _highlight.registerLanguages(builtinAllLanguages);
      _registered = true;
    }

    final TextSpan? span;
    try {
      final result = _highlight.highlight(code: lines.join('\n'), language: language);
      final renderer = TextSpanRenderer(base, syntaxTheme(colors, base));
      result.render(renderer);
      span = renderer.span;
    } on Object {
      // Разбор — дело ненадёжное: язык мог не подойти, файл — оказаться не тем,
      // чем выглядит. Показать текст без цвета всегда лучше, чем не показать.
      return const PlainHighlighter().highlight(lines, fileName: fileName, base: base);
    }

    if (span == null) {
      return const PlainHighlighter().highlight(lines, fileName: fileName, base: base);
    }
    return splitByLines(span, lines.length, base);
  }

  /// Режет дерево спанов на строки.
  ///
  /// Дерево приходит цельным, а рисуется по строке: сначала оно
  /// разворачивается в куски «текст плюс его стиль», потом куски
  /// раскладываются по строкам — кусок с переводом строки внутри делится.
  static List<TextSpan> splitByLines(TextSpan span, int lineCount, TextStyle base) {
    final lines = <List<InlineSpan>>[[]];

    void visit(InlineSpan node, TextStyle? inherited) {
      if (node is! TextSpan) {
        return;
      }
      final style = node.style ?? inherited;

      final text = node.text;
      if (text != null && text.isNotEmpty) {
        final parts = text.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) {
            lines.add([]);
          }
          if (parts[i].isNotEmpty) {
            lines.last.add(TextSpan(text: parts[i], style: style));
          }
        }
      }

      for (final child in node.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    visit(span, base);

    // Строк должно получиться ровно столько же, сколько их в документе: показ
    // обращается к ним по номеру. Разошлось — значит разбор потерял или
    // добавил перевод, и врать об этом нельзя.
    while (lines.length < lineCount) {
      lines.add([]);
    }
    return [for (var i = 0; i < lineCount; i++) TextSpan(style: base, children: lines[i])];
  }

  /// Язык по имени файла; null — подсвечивать нечем.
  ///
  /// Сначала по особым именам (`Makefile`, `Dockerfile` — у них расширения
  /// нет вовсе), потом по расширению.
  static String? languageOf(String fileName) {
    final name = fileName.toLowerCase();
    final byName = _byFileName[name];
    if (byName != null) {
      return byName;
    }

    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return null;
    }
    final extension = name.substring(dot + 1);

    final mapped = _byExtension[extension];
    if (mapped != null) {
      return mapped;
    }
    // Расширение часто и есть имя языка: `dart`, `python`, `ruby`, `lua`.
    return builtinAllLanguages.containsKey(extension) ? extension : null;
  }

  static const Map<String, String> _byFileName = {
    'makefile': 'makefile',
    'dockerfile': 'dockerfile',
    'cmakelists.txt': 'cmake',
    '.gitignore': 'properties',
    '.bashrc': 'bash',
    '.zshrc': 'bash',
  };

  /// Расширение → имя языка там, где они не совпадают.
  static const Map<String, String> _byExtension = {
    'yml': 'yaml',
    'js': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'rb': 'ruby',
    'sh': 'bash',
    'zsh': 'bash',
    'bash': 'bash',
    'h': 'cpp',
    'hpp': 'cpp',
    'cc': 'cpp',
    'cxx': 'cpp',
    'c': 'c',
    'cs': 'csharp',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'rs': 'rust',
    'go': 'go',
    'md': 'markdown',
    'markdown': 'markdown',
    'html': 'xml',
    'htm': 'xml',
    'xml': 'xml',
    'plist': 'xml',
    'svg': 'xml',
    'podspec': 'ruby',
    'gradle': 'gradle',
    'toml': 'ini',
    'cfg': 'ini',
    'conf': 'ini',
    'ps1': 'powershell',
    'm': 'objectivec',
    'mm': 'objectivec',
    'pl': 'perl',
    'tex': 'latex',
    'patch': 'diff',
    'log': 'accesslog',
  };
}
