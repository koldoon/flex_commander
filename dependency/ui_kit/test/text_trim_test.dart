import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обрезка пути слева: корень виден, хвост цел
/// (`docs/spec/panel-crumbs.md`, §2).
void main() {
  const style = TextStyle(fontSize: 14);
  const scaler = TextScaler.noScaling;

  double widthOf(String text) => textWidthOf(text, style, scaler);

  group('обрезка имени серединой (`docs/spec/name-trim.md`)', () {
    const name = 'Отчёт за третий квартал 2026 года, окончательный.xlsx';

    group('обрезка серединой по кускам (`docs/spec/panel-status-lines.md`, §3)', () {
      const glyph = TextStyle(fontFamily: 'icons');
      const name = 'очень длинное имя ссылки, которому не хватит ширины полосы.lnk';
      const target = '/Users/koldoon/Developer/Projects/цель ссылки.txt';
      const pieces = <TextPiece>[(name, null, false), (' → ', glyph, true), (target, null, false)];

      String plain(List<TextPiece> value) => value.map((piece) => piece.$1).join();

      test('влезает — не трогаем: тот же список кусков', () {
        final room = widthOf(plain(pieces)) + 1;

        expect(trimPiecesMiddle(pieces, style, room, scaler), same(pieces));
      });

      test('видны оба конца, и стрелка остаётся стрелкой', () {
        final trimmed = trimPiecesMiddle(pieces, style, widthOf(plain(pieces)) / 2, scaler);
        final text = plain(trimmed);

        expect(text, startsWith('очень'));
        expect(text, endsWith('.txt'), reason: 'цель ссылки — самое нужное в этой строке');
        expect(text, contains('…'));
        expect(
          trimmed.where((piece) => piece.$2 == glyph).map((piece) => piece.$1).join(),
          ' → ',
          reason: 'кусок со стрелкой набран своим шрифтом, как бы ни лёг разрез',
        );
      });

      test('разрез съедает и стрелку, когда места совсем нет', () {
        // Место на несколько знаков: стрелка в середине, и она уходит первой —
        // но начертание оставшегося не путается.
        final trimmed = trimPiecesMiddle(pieces, style, widthOf('очень…txt'), scaler);

        expect(plain(trimmed), contains('…'));
        expect(trimmed.every((piece) => piece.$1.isNotEmpty), isTrue, reason: 'пустых кусков не бывает');
      });

      test('соседние знаки одного начертания идут одним куском', () {
        final trimmed = trimPiecesMiddle(pieces, style, widthOf(plain(pieces)) / 2, scaler);

        for (var at = 1; at < trimmed.length; at++) {
          expect(trimmed[at].$2 == trimmed[at - 1].$2, isFalse, reason: 'иначе набор рвал бы кернинг на каждом знаке');
        }
      });
    });

    test('влезает — не трогаем', () {
      expect(trimTextMiddle(name, style, widthOf(name) + 1, scaler), name);
    });

    test('видны оба конца, и расширение в том числе', () {
      final trimmed = trimTextMiddle(name, style, widthOf(name) / 2, scaler);

      expect(trimmed, contains('…'));
      expect(trimmed, startsWith('Отчёт'));
      expect(trimmed.endsWith('.xlsx'), isTrue, reason: 'ради хвоста всё и затевалось');
      expect(widthOf(trimmed), lessThanOrEqualTo(widthOf(name) / 2));
    });

    test('показанного столько, сколько влезло', () {
      final room = widthOf(name) / 2;
      final trimmed = trimTextMiddle(name, style, room, scaler);

      // Ещё один знак — и не поместилось бы: иначе обрезка жадничает.
      expect(widthOf('$trimmed…'), greaterThan(room));
    });

    test('знак не рвётся посередине', () {
      // Одни лишь горы: куда ни придись разрез, он приходится на суррогатную
      // пару, — обрезка по кодовым единицам оставила бы половину знака.
      const emoji = '🏔🏔🏔🏔🏔🏔🏔🏔🏔🏔🏔🏔.jpg';
      final trimmed = trimTextMiddle(emoji, style, widthOf(emoji) / 2, scaler);

      final halves = trimmed.runes.where((rune) => rune >= 0xD800 && rune <= 0xDFFF);
      expect(halves, isEmpty, reason: 'половины знака в показанном не бывает');
      expect(trimmed, contains('…'));
    });

    test('места нет вовсе — имя возвращается как есть', () {
      expect(trimTextMiddle(name, style, 0, scaler), name);
      expect(trimTextMiddle(name, style, double.infinity, scaler), name);
    });

    test('в несколько строк мерка по строкам, а дыра всё равно одна', () {
      final room = widthOf(name) / 4;
      final trimmed = trimTextMiddle(name, style, room, scaler, maxLines: 2);

      expect('…'.allMatches(trimmed).length, 1);
      expect(spanFitsLines(TextSpan(text: trimmed, style: style), room, scaler, maxLines: 2), isTrue);
    });
  });

  test('влезает — не трогаем', () {
    expect(trimTextHead('/home/docs', style, widthOf('/home/docs') + 1, scaler), '/home/docs');
  });

  test('режется по целым звеньям, а не по буквам', () {
    // Обрубок посреди имени читается как другое имя: глаз принимает его за
    // настоящее и только потом замечает многоточие.
    const path = '/Users/koldoon/Developer/Petrosoft/qwickserve/docs';
    final trimmed = trimTextHead(path, style, widthOf('/…/Petrosoft/qwickserve/docs') + 1, scaler);

    expect(trimmed, '/…/Petrosoft/qwickserve/docs');
  });

  test('одно звено не влезает — режем его буквами: хвост важнее правила', () {
    final trimmed = trimTextHead(
      '/Users/koldoon/невероятно-длинное-имя-каталога',
      style,
      widthOf('…-каталога'),
      scaler,
    );

    expect(trimmed, startsWith('…'));
    expect(trimmed, endsWith('каталога'));
  });

  test('не влезает — остаётся корень, многоточие и хвост', () {
    final trimmed = trimTextHead(
      '/Users/koldoon/Developer/qwickserve/dist',
      style,
      widthOf('/…/qwickserve/dist'),
      scaler,
    );

    expect(trimmed, startsWith('/…'), reason: 'по корню видно, о каком диске речь');
    expect(trimmed, endsWith('dist'), reason: 'в конце тот каталог, о котором речь');
  });

  test('у адреса корень — это машина', () {
    const address = 'ssh://koldoon@shark/home/koldoon/very/deep/place';
    final trimmed = trimTextHead(address, style, widthOf('ssh://koldoon@shark/…/deep/place'), scaler);

    // Разделитель после корня свой: `ssh://koldoon@shark/…/deep/place` читается
    // как адрес, а `ssh://koldoon@shark…` — как обрубок имени машины.
    expect(trimmed, startsWith('ssh://koldoon@shark/…/'));
    expect(trimmed, endsWith('place'));
  });

  test('корень сам не влезает — режем без него', () {
    // Иначе от строки осталось бы одно начало, а нужен конец.
    const address = 'ssh://koldoon@shark/home/koldoon';
    final trimmed = trimTextHead(address, style, widthOf('…koldoon'), scaler);

    expect(trimmed, startsWith('…'));
    expect(trimmed, isNot(startsWith('ssh')));
  });

  test('не путь — обрезается как раньше', () {
    final trimmed = trimTextHead('очень длинная подпись команды', style, widthOf('…команды'), scaler);

    expect(trimmed, startsWith('…'));
    expect(trimmed, endsWith('команды'));
  });

  test('обрезанное помещается в отведённое', () {
    const path = '/Users/koldoon/Developer/Petrosoft/Qwickserve Flex Applications/dist';
    for (final width in [40.0, 80.0, 160.0, 320.0]) {
      expect(widthOf(trimTextHead(path, style, width, scaler)), lessThanOrEqualTo(width), reason: 'ширина $width');
    }
  });

  group('поместилось ли', () {
    test('пустая строка помещается всегда', () {
      expect(textFits('', style, 0, scaler), isTrue);
    });

    test('вставшая впритык — поместилась', () {
      // Иначе подсказка висела бы на каждой ровно уложившейся строке и
      // повторяла бы видимое.
      const name = 'readme.md';
      expect(textFits(name, style, widthOf(name), scaler), isTrue);
    });

    test('не влезла на волос — не поместилась', () {
      const name = 'readme.md';
      expect(textFits(name, style, widthOf(name) - 1, scaler), isFalse);
    });

    test('память не врёт при смене стиля', () {
      const name = 'очень длинное имя файла';
      const bigger = TextStyle(fontSize: 28);

      final small = textWidthOf(name, style, scaler);
      final large = textWidthOf(name, bigger, scaler);

      expect(large, greaterThan(small), reason: 'стиль — часть вопроса, а не догадка');
      expect(textWidthOf(name, style, scaler), small, reason: 'повторный ответ тот же');
    });

    test('память не врёт при смене крупности', () {
      const name = 'имя файла';
      final plain = textWidthOf(name, style, scaler);
      final scaled = textWidthOf(name, style, const TextScaler.linear(2));

      expect(scaled, greaterThan(plain));
    });
  });
}
