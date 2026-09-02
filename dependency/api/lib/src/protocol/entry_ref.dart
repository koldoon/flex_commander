/// Какая панель: у приложения их две, и обе адресуются именем.
enum PanelId { left, right }

/// Ссылка на объект — то, чем интерфейс называет ядру строку списка.
///
/// Ссылок ровно две, и они про разное (`docs/spec/client-server.md`, §4.2).
sealed class EntryRef {
  const EntryRef();

  /// То, что сейчас на экране: строка панели.
  ///
  /// [generation] растёт с каждым новым списком. Заявка на строку устаревшего
  /// списка отвергается, а не попадает в чужой файл: пока шло сообщение,
  /// каталог могли перечитать.
  const factory EntryRef.inPanel(PanelId panel, int index, int generation) = PanelEntryRef;

  /// Адрес со стороны: перетаскивание из системы, сценарий, буфер обмена,
  /// сохранённые настройки. Стоит разбора пути — того же, что делается и
  /// сейчас при открытии пути из окна.
  const factory EntryRef.path(String path) = PathEntryRef;
}

final class PanelEntryRef extends EntryRef {
  const PanelEntryRef(this.panel, this.index, this.generation);

  final PanelId panel;
  final int index;
  final int generation;

  @override
  String toString() => 'EntryRef(${panel.name}[$index]@$generation)';
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

  /// Помеченное в панели, а если не помечено ничего — объект под курсором.
  /// Это то самое правило, по которому работают все файловые операции.
  const factory Targets.marked(PanelId panel) = MarkedTargets;

  /// Только объект под курсором, что бы ни было помечено.
  const factory Targets.current(PanelId panel) = CurrentTargets;

  /// Названные пути: перетаскивание, сценарий, буфер обмена.
  const factory Targets.paths(List<String> paths) = PathTargets;
}

final class MarkedTargets extends Targets {
  const MarkedTargets(this.panel);

  final PanelId panel;
}

final class CurrentTargets extends Targets {
  const CurrentTargets(this.panel);

  final PanelId panel;
}

final class PathTargets extends Targets {
  const PathTargets(this.paths);

  final List<String> paths;
}
