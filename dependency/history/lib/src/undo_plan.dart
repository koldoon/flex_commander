import 'package:fc_api/fc_api.dart';

/// Что произойдёт при откате — словами, для окна подтверждения.
///
/// Не «уверены?», а перечень: «удалить 12 объектов в /dest, вернуть 3 из
/// корзины» (`docs/spec/operation-history.md`, §10).
class UndoPlan {
  const UndoPlan({required this.removes, required this.returns, required this.fromTrash, required this.places});

  factory UndoPlan.of(List<JournalEntry> journal) {
    var removes = 0;
    var returns = 0;
    var fromTrash = 0;
    final places = <String>{};

    for (final entry in journal) {
      switch (entry) {
        case Created(:final path):
          removes++;
          places.add(_directoryOf(path));
        case Moved(:final from, :final to):
          returns++;
          places
            ..add(_directoryOf(from))
            ..add(_directoryOf(to));
        case Trashed(:final from):
          fromTrash++;
          places.add(_directoryOf(from));
        case Destroyed():
          break;
      }
    }

    return UndoPlan(removes: removes, returns: returns, fromTrash: fromTrash, places: places.toList());
  }

  /// Сколько объектов будет удалено: это созданное работой.
  final int removes;

  /// Сколько вернётся туда, откуда уехало.
  final int returns;

  /// Сколько достанут из корзины.
  final int fromTrash;

  /// Каталоги, которых откат коснётся, — их и перечитывают после.
  final List<String> places;

  bool get isEmpty => removes == 0 && returns == 0 && fromTrash == 0;

  /// Перечень строкой: каждое дело своей фразой.
  String describe(Strings strings) {
    final parts = [
      if (removes > 0) strings.plural(removes, one: 'delete {n} object', other: 'delete {n} objects'),
      if (returns > 0) strings.plural(returns, one: 'move {n} object back', other: 'move {n} objects back'),
      if (fromTrash > 0)
        strings.plural(fromTrash, one: 'return {n} object from Trash', other: 'return {n} objects from Trash'),
    ];
    return parts.isEmpty ? strings.tr('Nothing to undo') : parts.join(', ');
  }

  static String _directoryOf(String path) {
    final at = path.lastIndexOf('/');
    return at <= 0 ? '/' : path.substring(0, at);
  }
}
