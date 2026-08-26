import 'package:fc_terminal/fc_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор последнего токена: чистая работа со строкой, и вариантов у неё
/// больше, чем у всего дополнения вместе взятого.
void main() {
  CompletionToken parse(String line, [int? cursor]) => CompletionToken.parse(line, cursor ?? line.length);

  test('простое слово — это имя в каталоге панели', () {
    final token = parse('cd doc');

    expect(token.directory, isEmpty);
    expect(token.prefix, 'doc');
    expect(token.start, 3);
    expect(token.end, 6);
  });

  test('путь со слэшем делится на каталог и начало имени', () {
    expect(parse('cp sub/fi').directory, 'sub/');
    expect(parse('cp sub/fi').prefix, 'fi');

    expect(parse('cat /etc/pas').directory, '/etc/');
    expect(parse('cat /etc/pas').prefix, 'pas');

    expect(parse('ls ~/Doc').directory, '~/');
    expect(parse('ls ~/Doc').prefix, 'Doc');
  });

  test('каталог целиком — начало имени пустое', () {
    final token = parse('ls /etc/');

    expect(token.directory, '/etc/');
    expect(token.prefix, isEmpty);
  });

  test('строка кончается пробелом — токен пуст: показать всё, что здесь есть', () {
    final token = parse('ls ');

    expect(token.isEmpty, isTrue);
    expect(token.start, 3);
    expect(token.end, 3);
  });

  test('пустая строка тоже разбирается', () {
    expect(parse('').isEmpty, isTrue);
  });

  test('экранированный пробел имя не разрывает', () {
    final token = parse(r'cat my\ rep');

    expect(token.prefix, 'my rep');
    expect(token.start, 4);
  });

  test('кавычка запоминается, а токен начинается с неё', () {
    final token = parse("cat 'my rep");

    expect(token.quote, "'");
    expect(token.prefix, 'my rep');
    expect(token.start, 4, reason: 'заменяется токен вместе с кавычкой');
  });

  test('закрытая кавычка на разбор следующего токена не влияет', () {
    final token = parse("cp 'a b' doc");

    expect(token.quote, isEmpty);
    expect(token.prefix, 'doc');
    expect(token.start, 9);
  });

  test('дополняется то, что под курсором, а не конец строки', () {
    // Курсор после `doc`, а дальше ещё один аргумент.
    final token = parse('cp doc /tmp', 6);

    expect(token.prefix, 'doc');
    expect(token.end, 6);
  });

  test('общее начало находится и отсутствует', () {
    expect(commonPrefix(['docs', 'downloads', 'dossier']), 'do');
    expect(commonPrefix(['docs']), 'docs');
    expect(commonPrefix(['alpha', 'beta']), isEmpty);
    expect(commonPrefix([]), isEmpty);
  });
}
