import '../serialization.dart';

/// Шаг сессии: каталог, в котором она была, и место курсора в нём.
///
/// Из таких шагов складывается история переходов
/// (`docs/spec/session-history.md`). Значение, а не запись в журнале: шаг
/// живёт и в настройках, и в заявке через границу, а по обе стороны он один и
/// тот же.
class PathStep implements Serializable {
  PathStep({this.path = '', this.cursor = ''});

  /// Полная строка пути, со схемой источника (`ssh://user@host/etc`).
  ///
  /// Со схемой — потому что шаг обязан возвращать туда же, откуда ушли, а не в
  /// одноимённый каталог другого источника. Пароль в неё не попадает: он
  /// вырезается ещё на входе, как и в истории адресов.
  String path;

  /// Имя объекта под курсором; пусто — курсор встанет в начало списка.
  ///
  /// **Имя, а не номер строки:** за время между шагами в каталоге прибавится
  /// или убавится файлов, и номер привёл бы курсор не туда. То же правило, что
  /// у курсора сессии.
  String cursor;

  /// Шагу без пути в истории делать нечего: вернуться по нему некуда.
  bool get isEmpty => path.isEmpty;

  PathStep copyWith({String? path, String? cursor}) => PathStep(path: path ?? this.path, cursor: cursor ?? this.cursor);

  @override
  void toMap(Map<String, dynamic> m) {
    m['path'] = path;
    if (cursor.isNotEmpty) {
      m['cursor'] = cursor;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    path = extract(path, m['path']);
    cursor = extract(cursor, m['cursor']);
  }

  @override
  bool operator ==(Object other) => other is PathStep && other.path == path && other.cursor == cursor;

  @override
  int get hashCode => Object.hash(path, cursor);

  @override
  String toString() => 'PathStep($path${cursor.isEmpty ? '' : ' → $cursor'})';
}
