import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Нарезка строк дерева столбцами (`docs/spec/panel-view-columns.md`, §4).
///
/// Без виджетов: нарезка — значение, и проверяется она значением. Строки здесь
/// пишутся руками, как их присылает ядро: уровень, раскрытость и путь.
void main() {
  FileEntry dir(String path, {required int level, bool open = false}) =>
      FileEntry(name: path.split('/').last, kind: EntryKind.directory, path: path, level: level, isOpen: open);

  FileEntry file(String path, {required int level}) =>
      FileEntry(name: path.split('/').last, kind: EntryKind.file, path: path, level: level);

  /// Дерево, раскрытое до `/home/lib`, и рядом — раскрытая ветвь в стороне.
  ///
  /// Так это и выглядит живьём: раскрытое общее с деревом, и по дороге в
  /// цепочку попадает чужое поддерево.
  List<FileEntry> tree() => [
    /* 0 */ dir('/', level: 0, open: true),
    /* 1 */ dir('/home', level: 1, open: true),
    /* 2 */ dir('/home/docs', level: 2, open: true), // раскрыто в стороне
    /* 3 */ file('/home/docs/notes.txt', level: 3),
    /* 4 */ dir('/home/lib', level: 2, open: true),
    /* 5 */ dir('/home/lib/src', level: 3),
    /* 6 */ file('/home/lib/app.dart', level: 3),
    /* 7 */ file('/home/main.dart', level: 2),
    /* 8 */ dir('/other', level: 1),
  ];

  List<int> rowsOf(ColumnChain chain, int column) => chain.columns[column].rows;

  test('столбец — дети своего предка, а не отрезок списка', () {
    final rows = tree();
    final chain = ColumnChain.of(rows, 6); // курсор на `/home/lib/app.dart`

    expect(chain.columns.length, 3);
    expect(rowsOf(chain, 0), [1, 8], reason: 'содержимое корня');
    expect(rowsOf(chain, 1), [2, 4, 7], reason: 'содержимое /home');
    expect(rowsOf(chain, 2), [5, 6], reason: 'содержимое /home/lib');
  });

  test('корневая строка столбцом не рисуется', () {
    final chain = ColumnChain.of(tree(), 6);

    // Столбец 0 — содержимое корня: колонка из одной строки `/` не сообщает
    // ничего, а место занимает.
    expect(chain.columns.first.owner, 0);
    expect(rowsOf(chain, 0), isNot(contains(0)));
  });

  test('раскрытое в стороне не показывается, а его родитель — да', () {
    final chain = ColumnChain.of(tree(), 6);

    // `/home/docs` раскрыт, и его содержимое лежит в списке между `/home` и
    // `/home/lib`. В столбце `/home` сам он есть, а его детей там нет.
    expect(rowsOf(chain, 1), contains(2), reason: 'родитель — сосед по каталогу');
    expect(rowsOf(chain, 1), isNot(contains(3)), reason: 'а его содержимое — чужое поддерево');
  });

  test('курсор на файле не даёт столбца правее', () {
    final chain = ColumnChain.of(tree(), 7); // `/home/main.dart`

    expect(chain.columns.length, 2);
    expect(chain.current, 1, reason: 'курсор в столбце своего каталога');
    expect(chain.columns.last.selected, 7);
  });

  test('закрытая ветвь столбца правее тоже не даёт', () {
    final chain = ColumnChain.of(tree(), 5); // `/home/lib/src`, не раскрыт

    expect(chain.columns.length, 3);
    expect(chain.current, 2);
  });

  test('раскрытая ветвь показывает содержимое справа', () {
    final chain = ColumnChain.of(tree(), 4); // `/home/lib`, раскрыт

    expect(chain.columns.length, 3, reason: 'справа — содержимое того, на чём стоим');
    expect(chain.current, 1, reason: 'а курсор по-прежнему в своём столбце');
    expect(chain.columns.last.selected, -1, reason: 'в правом столбце ещё ничего не выбрано');
  });

  test('выбранное видно в каждом столбце — это и есть путь', () {
    final chain = ColumnChain.of(tree(), 6);

    expect([for (final column in chain.columns) column.selected], [1, 4, 6]);
  });

  test('курсор на корне: столбец есть, курсора в нём нет', () {
    // Так бывает: курсор встал на корень в дереве, а вид переключили после.
    final chain = ColumnChain.of(tree(), 0);

    expect(chain.columns.length, 1, reason: 'содержимое корня показать всё равно есть чем');
    expect(chain.current, -1);
    expect(chain.columns.single.selected, -1);
  });

  test('раскрытый пустой каталог даёт пустой столбец, а не отсутствие его', () {
    final rows = [dir('/', level: 0, open: true), dir('/empty', level: 1, open: true)];
    final chain = ColumnChain.of(rows, 1);

    // Иначе «здесь пусто» и «сюда не входили» выглядели бы одинаково.
    expect(chain.columns.length, 2);
    expect(chain.columns.last.rows, isEmpty);
  });

  test('строк нет — нарезать нечего', () {
    expect(ColumnChain.of(const [], 0).isEmpty, isTrue);
    expect(ColumnChain.of(tree(), -1).isEmpty, isTrue);
  });

  test('пересчёта нет, пока не сменились ни строки, ни курсор', () {
    // Пока ядро считает размеры каталогов, список приходит новым по нескольку
    // раз в секунду — нарезка на каждую перерисовку стоила бы прохода по всем
    // строкам десятки раз в секунду.
    final memo = ChainMemo();
    final rows = tree();

    final first = memo.of(rows, 6);
    expect(identical(memo.of(rows, 6), first), isTrue, reason: 'тот же ответ, а не такой же');

    expect(identical(memo.of(rows, 7), first), isFalse, reason: 'курсор сменился');
    expect(identical(memo.of(tree(), 7), memo.of(rows, 7)), isFalse, reason: 'список сменился');
  });
}
