import 'package:fc_api/fc_api.dart';

/// Один столбец вида «Столбцы»: содержимое одного каталога.
///
/// Строки — **номерами** в общем списке, а не значениями: по номеру ходит
/// курсор, по номеру же считается отрезок пометки, и хранить рядом второй
/// способ назвать ту же строку значило бы однажды их развести.
class ChainColumn {
  const ChainColumn({required this.owner, required this.rows, required this.selected});

  /// Строка каталога, чьё содержимое показывает столбец.
  ///
  /// Её путь — ключ, которым столбец опознаётся снаружи: по нему хранятся
  /// ширина и прокрутка. Номера для этого не годятся: цепочка укорачивается и
  /// растёт, а номера при этом съезжают.
  final int owner;

  /// Строки столбца — дети [owner], в порядке списка.
  final List<int> rows;

  /// Строка, из которой вышли в столбец правее; -1 — такой нет.
  ///
  /// В последнем столбце это строка под курсором. Она же остаётся
  /// подсвеченной, когда курсор ушёл дальше вправо: иначе от пути был бы виден
  /// только его конец.
  final int selected;
}

/// Цепочка столбцов — путь курсора, разложенный слева направо.
///
/// Значение без виджетов: нарезка проверяется без `pumpWidget`, а вид получает
/// готовый ответ. Спецификация — `docs/spec/panel-view-columns.md`, §4.
class ColumnChain {
  const ColumnChain({required this.columns, required this.current});

  static const ColumnChain empty = ColumnChain(columns: [], current: -1);

  final List<ChainColumn> columns;

  /// Столбец, в котором стоит курсор; -1 — курсор ни в одном из них.
  ///
  /// Так бывает ровно в одном случае: курсор на корневой строке, а она
  /// столбцом не рисуется — столбец 0 это её содержимое. Случай не выдуманный:
  /// курсор мог встать на корень в дереве, а вид переключили после.
  final int current;

  bool get isEmpty => columns.isEmpty;

  /// Нарезать строки дерева столбцами.
  ///
  /// Правило: столбец `k` — строки уровня `k` внутри поддерева той строки
  /// уровня `k−1`, что стоит на цепочке курсора. Цепочка считается подъёмом по
  /// предкам, как её считает дерево (`TreeBranchCommand.parentRowOf`).
  ///
  /// **Столбец — список номеров, а не отрезок**: между соседями по каталогу
  /// может лежать чужое раскрытое поддерево. Раскрывали его в дереве, память
  /// раскрытого общая — и пропускается оно по уровню, а не по границам.
  static ColumnChain of(List<FileEntry> rows, int cursor) {
    if (cursor < 0 || cursor >= rows.length) {
      return empty;
    }

    final chain = _ancestorsOf(rows, cursor);
    final columns = <ChainColumn>[];
    for (var at = 0; at < chain.length; at++) {
      final owner = chain[at];
      // Столбец правее есть ровно у раскрытого каталога. У файла и у закрытой
      // ветви содержимого не видно — ни в списке строк, ни на экране.
      if (!rows[owner].isOpen) {
        break;
      }
      columns.add(
        ChainColumn(owner: owner, rows: _childrenOf(rows, owner), selected: at + 1 < chain.length ? chain[at + 1] : -1),
      );
    }

    // Курсор стоит в предпоследнем звене цепочки: последнее — он сам, а
    // столбец, который его показывает, принадлежит его родителю.
    final current = chain.length - 2;
    return ColumnChain(columns: columns, current: current.clamp(-1, columns.length - 1));
  }

  /// Путь от корня до строки под курсором — номерами строк, корень первым.
  ///
  /// Все предки раскрыты по построению списка: строка попадает в него только
  /// тогда, когда раскрыт тот, в ком она лежит.
  static List<int> _ancestorsOf(List<FileEntry> rows, int cursor) {
    final chain = <int>[cursor];
    var want = rows[cursor].level - 1;
    for (var at = cursor - 1; at >= 0 && want >= 0; at--) {
      if (rows[at].level == want) {
        chain.insert(0, at);
        want--;
      }
    }
    return chain;
  }

  /// Дети строки [owner] — по уровню, а не по соседству.
  static List<int> _childrenOf(List<FileEntry> rows, int owner) {
    final level = rows[owner].level;
    final children = <int>[];
    for (var at = owner + 1; at < rows.length; at++) {
      final row = rows[at];
      // Кончилось поддерево владельца — кончился и столбец.
      if (row.level <= level) {
        break;
      }
      if (row.level == level + 1) {
        children.add(at);
      }
    }
    return children;
  }
}

/// Памятка нарезки: пересчёт только тогда, когда сменились строки или курсор.
///
/// Без неё нарезка шла бы на каждую перерисовку, а пока ядро считает размеры
/// каталогов, список приходит новым по нескольку раз в секунду
/// (`docs/spec/directory-sizes.md`). На этом уже погорело дерево.
///
/// Сравнение строк — **по тождеству**: равенство десяти тысяч значений стоило
/// бы дороже самой нарезки, а новый список ядро присылает новым объектом.
class ChainMemo {
  List<FileEntry>? _rows;
  int _cursor = -1;
  ColumnChain _chain = ColumnChain.empty;

  ColumnChain of(List<FileEntry> rows, int cursor) {
    if (identical(rows, _rows) && cursor == _cursor) {
      return _chain;
    }
    _rows = rows;
    _cursor = cursor;
    return _chain = ColumnChain.of(rows, cursor);
  }
}
