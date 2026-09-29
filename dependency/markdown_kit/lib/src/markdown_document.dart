import 'dart:convert';
import 'dart:math' as math;

import 'package:markdown/markdown.dart' as md;

/// Разобранный документ: узлы верхнего уровня — по одному на блок.
///
/// Разбор отделён от показа затем, чтобы документ строился **лениво**:
/// библиотека складывает все виджеты разом и отдаёт их в `ListView(children:)`
/// (`docs/spec/markdown-viewer.md`, §5), а на файле в треть мегабайта — а
/// `docs/roadmap.md` этого проекта именно таков — это тысячи виджетов до
/// первого кадра.
class FcMarkdownDocument {
  FcMarkdownDocument._(this.source, this.nodes);

  /// Разобрать текст документа.
  factory FcMarkdownDocument.parse(String source) {
    final document = md.Document(extensionSet: extensions, encodeHtml: false);
    final lines = const LineSplitter().convert(source);

    return FcMarkdownDocument._(source, document.parseLines(lines));
  }

  /// Набор синтаксиса — свой, а не готовый.
  ///
  /// Взят `gitHubWeb` без **одного** правила: `AlertBlockSyntax` делает из
  /// `> [!NOTE]` узел `div`, а показ такого тега не знает — `div` нет среди его
  /// блочных, и разбор падает с «Too many elements» прямо в отрисовке. Это не
  /// наша оплошность и не чинится настройкой: библиотека умеет ровно свои теги
  /// (`markdown-viewer.md`, §12).
  ///
  /// Всё остальное из `gitHubWeb` на месте: таблицы, списки задач, сноски
  /// (они есть уже в `gitHubFlavored`), якоря заголовков и эмодзи.
  ///
  /// Один и тот же набор идёт и в разбор, и в показ — иначе узлы разъедутся.
  static final md.ExtensionSet extensions = md.ExtensionSet(
    List<md.BlockSyntax>.unmodifiable(<md.BlockSyntax>[
      const md.FencedCodeBlockSyntax(),
      const md.HeaderWithIdSyntax(),
      const md.SetextHeaderWithIdSyntax(),
      const md.TableSyntax(),
      const md.UnorderedListWithCheckboxSyntax(),
      const md.OrderedListWithCheckboxSyntax(),
      const md.FootnoteDefSyntax(),
    ]),
    List<md.InlineSyntax>.unmodifiable(<md.InlineSyntax>[
      md.InlineHtmlSyntax(),
      md.StrikethroughSyntax(),
      md.EmojiSyntax(),
      md.AutolinkExtensionSyntax(),
    ]),
  );

  /// Исходный текст — его показывает Raw и по нему ищут в нём.
  final String source;

  /// Узлы верхнего уровня: по одному на блок документа.
  final List<md.Node> nodes;

  /// Сколько блоков в документе.
  int get length => nodes.length;

  /// Видимый текст документа — то, что человек читает, строками.
  ///
  /// По нему и ищут: искать по разметке значило бы находить звёздочки и
  /// решётки, которых на экране нет (`docs/spec/markdown-viewer.md`, §9).
  late final String plainText = _projected.$1.join('\n');

  /// Строка [plainText] → номер блока в [nodes].
  ///
  /// Так найденное превращается в место на экране: поиск говорит строку,
  /// а показу нужен блок, который надо показать.
  late final List<int> blockOfLine = _projected.$2;

  /// Обход делается один раз: строки и их блоки считаются вместе.
  late final (List<String>, List<int>) _projected = _projection();

  /// Номер строки исходника, с которой начинается блок.
  ///
  /// Нужна, чтобы `F5` не терял место чтения: свёрстанный документ и исходник
  /// разной длины, и общего у них только «какой блок сейчас сверху»
  /// (`docs/spec/markdown-viewer.md`, §8).
  ///
  /// **Считается поиском, а не разбором.** Позиций узлов библиотека не хранит
  /// вовсе: `Element` знает тег, детей и атрибуты — и ничего о том, откуда он
  /// взялся. Поэтому блоки сопоставляются с исходником по тексту, курсором
  /// вперёд: найденное не может оказаться выше предыдущего.
  late final List<int> sourceLineOfBlock = _sourceLines();

  /// В каком блоке лежит строка исходника.
  ///
  /// Обратная сторона [sourceLineOfBlock]: `F5` из исходника в свёрстанный.
  int blockOfSourceLine(int line) {
    final at = sourceLineOfBlock;
    if (at.isEmpty) {
      return 0;
    }

    var low = 0;
    var high = at.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (at[middle] <= line) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    return low;
  }

  /// Докуда ищем строку блока, прежде чем сдаться.
  ///
  /// Без предела один не нашедшийся блок прочёсывал бы весь файл, и на
  /// документе в треть мегабайта это стоило бы заметно. Не нашли — оставляем
  /// курсор: место чтения сместится, но не улетит.
  static const int _searchWindow = 500;

  List<int> _sourceLines() {
    final lines = const LineSplitter().convert(source);
    final at = <int>[];
    var cursor = 0;

    for (final node in nodes) {
      // Разделителю читать нечего — его ищут по виду, а не по тексту.
      final rule = node is md.Element && node.tag == 'hr';
      final key = rule ? '' : _searchKey(_linesOf(node).firstOrNull ?? '');
      var found = -1;

      if (rule || key.isNotEmpty) {
        final limit = math.min(lines.length, cursor + _searchWindow);
        for (var i = cursor; i < limit; i++) {
          if (rule ? _isRule(lines[i]) : _matches(lines[i], key)) {
            found = i;
            break;
          }
        }
      }

      if (found < 0) {
        at.add(cursor);
        continue;
      }

      // У врезки кода первая строка — уже код, а начинается она оградой.
      if (node is md.Element && node.tag == 'pre' && found > 0 && _isFence(lines[found - 1])) {
        found--;
      }

      at.add(found);
      cursor = found + 1;
    }

    return at;
  }

  /// Та ли это строка исходника, с которой начинается блок.
  ///
  /// Номер нумерованного списка в узел не попадает: `1. раз` даёт «раз». Его и
  /// снимаем со строки исходника вторым заходом — иначе ни один `ol` не нашёлся
  /// бы, и список уезжал бы к предыдущему блоку.
  static bool _matches(String line, String key) =>
      _searchKey(line).startsWith(key) || _searchKey(line, withoutNumber: true).startsWith(key);

  static final RegExp _leadingDigits = RegExp(r'^\p{N}+', unicode: true);

  /// Черта на всю строку: `---`, `***` или `___`, хоть с пробелами.
  static bool _isRule(String line) => _rule.hasMatch(line);

  static final RegExp _rule = RegExp(r'^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$');

  static bool _isFence(String line) {
    final text = line.trimLeft();

    return text.startsWith('```') || text.startsWith('~~~');
  }

  /// По чему узнаём строку: одни буквы и цифры, в нижнем регистре.
  ///
  /// Разметку сравнивать нельзя: в исходнике стоит `## Заголовок` или
  /// `**жирный** текст`, а в узле — уже `Заголовок` и `жирный текст`. Выкинув
  /// всё, кроме букв и цифр, получаем то общее, что у них есть.
  ///
  /// Берём начало строки, а не её целиком: абзац в узле склеен, а в исходнике
  /// разбит по ширине.
  static String _searchKey(String text, {bool withoutNumber = false}) {
    var head = text.split('\n').first.toLowerCase().replaceAll(_noise, '');
    if (withoutNumber) {
      // Снимаем **до** обрезки: иначе ключ строки выходит короче искомого на
      // длину номера, и `startsWith` не срабатывает никогда.
      head = head.replaceFirst(_leadingDigits, '');
    }

    return head.length <= _keyLength ? head : head.substring(0, _keyLength);
  }

  static const int _keyLength = 24;

  static final RegExp _noise = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  (List<String>, List<int>) _projection() {
    final lines = <String>[];
    final blocks = <int>[];

    for (var index = 0; index < nodes.length; index++) {
      for (final line in _linesOf(nodes[index])) {
        lines.add(line);
        blocks.add(index);
      }
    }

    return (lines, blocks);
  }

  /// Во что превращается узел на экране — построчно.
  ///
  /// Пустых строк не даём: поиск по ним не ходит, а номера строк они бы
  /// сдвинули.
  static List<String> _linesOf(md.Node node) {
    if (node is! md.Element) {
      final text = node.textContent.trim();

      return text.isEmpty ? const [] : [text];
    }

    switch (node.tag) {
      // Врезка кода — своими строками: в ней ищут так же, как в файле.
      case 'pre':
        return node.textContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

      // Ячейки строки таблицы — через табуляцию: на экране они стоят в ряд.
      case 'tr':
        final cells = node.children?.whereType<md.Element>().map((cell) => cell.textContent.trim()) ?? const [];
        final row = cells.where((cell) => cell.isNotEmpty).join('\t');

        return row.isEmpty ? const [] : [row];

      // Обёртки: своей строки не дают, но их содержимое — даёт.
      case 'ul':
      case 'ol':
      case 'blockquote':
      case 'table':
      case 'thead':
      case 'tbody':
      case 'section':
        return [for (final child in node.children ?? const <md.Node>[]) ..._linesOf(child)];

      // Разделитель читать нечего.
      case 'hr':
        return const [];

      default:
        final text = node.textContent.trim();

        return text.isEmpty ? const [] : [text];
    }
  }
}
