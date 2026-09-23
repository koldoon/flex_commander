/// Личность сессии панели.
///
/// Именно сессии, а не стороны: сторон на экране две и они на месте
/// (`ViewportPosition`), а сессий в стороне бывает несколько — столбцами
/// комбинированного вида или вкладками. Какая где показана, знает экран; ядро
/// знает только сессии (`docs/spec/panel-sessions.md`, §4).
///
/// [left] и [right] — две первые сессии, те самые, что стоят в сторонах при
/// запуске. Имена у них прежние: панелей по одной на сторону, пока не
/// попросили больше.
class PanelId {
  const PanelId(this.value);

  static const PanelId left = PanelId(0);
  static const PanelId right = PanelId(1);

  /// Номер сессии: растёт с каждой заведённой.
  final int value;

  /// Имя для отладки и сообщений; заведённые на ходу зовутся по номеру.
  String get name => switch (value) {
    0 => 'left',
    1 => 'right',
    _ => 'panel$value',
  };

  @override
  bool operator ==(Object other) => other is PanelId && other.value == value;

  @override
  int get hashCode => value;

  @override
  String toString() => 'PanelId($name)';
}

/// Ссылка на объект — то, чем интерфейс называет ядру строку списка.
///
/// Ссылок ровно две, и они про разное (`docs/spec/client-server.md`, §4.2).
sealed class EntryRef {
  const EntryRef();

  /// То, что сейчас на экране: строка панели.
  ///
  /// Называется она **личностью** ([FileEntry.id]), а не местом в списке, и
  /// разбирает её сама сессия — по своим строкам. Так ссылка переживает и
  /// прирост списка, и перечитывание: узел остаётся тем же, где бы он ни
  /// оказался (`docs/spec/client-server.md`, §5.5а).
  ///
  /// [path] — запасной ключ: перечитанный каталог рождает новые узлы, и
  /// личности у них новые, а путь тот же. Пусто у «..»: у неё нет пути, и
  /// подтверждать личность ей нечем.
  const factory EntryRef.inPanel(PanelId panel, int id, {String path}) = PanelEntryRef;

  /// Адрес со стороны: перетаскивание из системы, сценарий, буфер обмена,
  /// сохранённые настройки. Стоит разбора пути — того же, что делается и
  /// сейчас при открытии пути из окна.
  const factory EntryRef.path(String path) = PathEntryRef;
}

final class PanelEntryRef extends EntryRef {
  const PanelEntryRef(this.panel, this.id, {this.path = ''});

  final PanelId panel;

  /// Личность строки — [FileEntry.id].
  final int id;

  /// Путь строки: подтверждение личности и запасной ключ.
  final String path;

  @override
  String toString() => 'EntryRef(${panel.name}#$id${path.isEmpty ? '' : ' $path'})';
}

final class PathEntryRef extends EntryRef {
  const PathEntryRef(this.path);

  final String path;

  @override
  String toString() => 'EntryRef($path)';
}

/// Над чем работать — **именем набора**, а не перечислением.
///
/// Пометка живёт в ядре, и разворачивать её в список объектов должно оно:
/// гонять через границу пять тысяч путей затем, чтобы та сторона нашла по ним
/// те же узлы, которые только что отдала, — работа впустую
/// (`docs/spec/client-server.md`, §4.3).
sealed class Targets {
  const Targets();

  /// Помеченное в панели, а если не помечено ничего — строка [under].
  /// Это то самое правило, по которому работают все файловые операции.
  ///
  /// Строку **называет тот, кто заводит работу**, а не ядро по своему курсору:
  /// курсор принадлежит экрану, и ядро, отставшее на несколько подтверждений,
  /// взяло бы не ту строку, которую человек видел, когда нажал `F8`
  /// (`docs/spec/client-server.md`, §5.6). null — строки нет вовсе: пустой
  /// список или «..» под курсором.
  const factory Targets.marked(PanelId panel, {required EntryRef? under}) = MarkedTargets;

  /// Только названная строка, что бы ни было помечено.
  const factory Targets.row(EntryRef row) = RowTargets;

  /// Названные пути: перетаскивание, сценарий, буфер обмена.
  const factory Targets.paths(List<String> paths) = PathTargets;
}

final class MarkedTargets extends Targets {
  const MarkedTargets(this.panel, {required this.under});

  final PanelId panel;

  /// Чем работать, если не помечено ничего; null — нечем.
  final EntryRef? under;
}

final class RowTargets extends Targets {
  const RowTargets(this.row);

  final EntryRef row;
}

final class PathTargets extends Targets {
  const PathTargets(this.paths);

  final List<String> paths;
}
