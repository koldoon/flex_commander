import 'package:fc_api/fc_api.dart';
// Обрезка краёв имени — та же, которой кончает одиночное переименование: два
// окна, спрашивающих имя, обязаны понимать его одинаково (`rename.md`, §5а).
import 'package:fc_core_api/fc_core_api.dart';

/// Что набрано в окне группового переименования.
///
/// Одним значением: оно же — содержимое сохранённого набора и запись в файле
/// настроек, поэтому вид его `toMap`/`fromMap` — это формат на диске
/// (`docs/spec/multi-rename.md`, §2).
class RenameSpec {
  const RenameSpec({
    this.nameMask = '[N]',
    this.extensionMask = '[E]',
    this.find = '',
    this.replace = '',
    this.regexp = false,
    this.caseSensitive = false,
    this.nameCase = RenameCase.keep,
    this.extensionCase = RenameCase.keep,
    this.counter = const RenameCounter(),
    this.byCreated = false,
  });

  factory RenameSpec.fromMap(Map<String, Object?> map) => RenameSpec(
    nameMask: map['nameMask'] as String? ?? '[N]',
    extensionMask: map['extensionMask'] as String? ?? '[E]',
    find: map['find'] as String? ?? '',
    replace: map['replace'] as String? ?? '',
    regexp: map['regexp'] as bool? ?? false,
    caseSensitive: map['caseSensitive'] as bool? ?? false,
    nameCase: _caseOf(map['nameCase'] as String?),
    extensionCase: _caseOf(map['extensionCase'] as String?),
    counter: RenameCounter(
      start: map['start'] as int? ?? 1,
      step: map['step'] as int? ?? 1,
      digits: map['digits'] as int? ?? 1,
    ),
    byCreated: map['byCreated'] as bool? ?? false,
  );

  /// Маски имени и расширения — два поля, как в MRT: основу и расширение
  /// правят по отдельности чаще, чем целиком.
  final String nameMask;
  final String extensionMask;

  /// «Найти → заменить» и как это читать.
  final String find;
  final String replace;
  final bool regexp;
  final bool caseSensitive;

  /// Регистр — свой у имени и свой у расширения (§6).
  final RenameCase nameCase;
  final RenameCase extensionCase;

  final RenameCounter counter;

  /// Какая дата подставляется `[Y]`, `[M]`…: изменения или создания.
  final bool byCreated;

  RenameMask get name => RenameMask.parse(nameMask);

  RenameMask get extension => RenameMask.parse(extensionMask);

  NameReplacement get replacement => NameReplacement.parse(find, replace, regexp: regexp, caseSensitive: caseSensitive);

  /// Годно ли набранное. Негодное гасит применение и объясняется у поля.
  bool get isValid => name.isValid && extension.isValid && replacement.isValid;

  /// Что именно не понято; null — всё понято.
  String? get problem =>
      name.problem ?? extension.problem ?? (replacement.isValid ? null : 'The expression is not understood');

  Map<String, Object?> toMap() => {
    'nameMask': nameMask,
    'extensionMask': extensionMask,
    'find': find,
    'replace': replace,
    'regexp': regexp,
    'caseSensitive': caseSensitive,
    'nameCase': nameCase.name,
    'extensionCase': extensionCase.name,
    'start': counter.start,
    'step': counter.step,
    'digits': counter.digits,
    'byCreated': byCreated,
  };

  RenameSpec copyWith({
    String? nameMask,
    String? extensionMask,
    String? find,
    String? replace,
    bool? regexp,
    bool? caseSensitive,
    RenameCase? nameCase,
    RenameCase? extensionCase,
    RenameCounter? counter,
    bool? byCreated,
  }) => RenameSpec(
    nameMask: nameMask ?? this.nameMask,
    extensionMask: extensionMask ?? this.extensionMask,
    find: find ?? this.find,
    replace: replace ?? this.replace,
    regexp: regexp ?? this.regexp,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    nameCase: nameCase ?? this.nameCase,
    extensionCase: extensionCase ?? this.extensionCase,
    counter: counter ?? this.counter,
    byCreated: byCreated ?? this.byCreated,
  );

  static RenameCase _caseOf(String? name) =>
      RenameCase.values.firstWhere((value) => value.name == name, orElse: () => RenameCase.keep);
}

/// Что со строкой станет.
enum RenameStatus {
  /// Имя не меняется.
  unchanged,

  /// Имя меняется, и это можно применять.
  renamed,

  /// Такое же новое имя получил кто-то ещё в этом же каталоге.
  duplicate,

  /// Имя уже занято в каталоге — тем, кто никуда не уезжает.
  taken;

  bool get collides => this == RenameStatus.duplicate || this == RenameStatus.taken;
}

/// Строка предпросмотра: было и станет.
class RenameRow {
  const RenameRow({required this.entry, required this.to, required this.status});

  final FileEntry entry;

  String get from => entry.name;

  final String to;
  final RenameStatus status;
}

/// План переименования: то, что видно в таблице, и то, что уйдёт работе.
///
/// Считается **в окне** и целиком: имена в ядро едут готовыми, а маски туда не
/// едут вовсе (`docs/spec/multi-rename.md`, §2).
class RenamePlan {
  const RenamePlan(this.rows);

  /// Собрать план.
  ///
  /// [entries] — цели в том порядке, в каком их видно в панели: по нему же
  /// считается номер счётчика (§5). [naming] — та же служба, что делит имя на
  /// основу и расширение в колонках: составные расширения разбирает она.
  /// [taken] — имена, уже занятые в каталогах: каталог → имена.
  factory RenamePlan.build(
    List<FileEntry> entries,
    RenameSpec spec, {
    required FileNaming naming,
    Map<String, Set<String>> taken = const {},
  }) {
    if (!spec.isValid) {
      // Негодная маска ничего не обещает: строки стоят как были, а применение
      // гасит окно.
      return RenamePlan([
        for (final entry in entries) RenameRow(entry: entry, to: entry.name, status: RenameStatus.unchanged),
      ]);
    }
    final name = spec.name;
    final extension = spec.extension;
    final replacement = spec.replacement;

    // Кто из занявших имя сам уезжает: его имя освободится, и столкновением
    // это не считается — это порядок, и его считает работа (§9).
    final leaving = <String>{for (final entry in entries) _keyOf(entry.directoryPath, entry.name)};

    final proposed = <String>[];
    final counts = <String, int>{};

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final split = naming.split(entry.name);
      final subject = RenameSubject(
        base: split.base,
        extension: split.extension,
        parentName: _lastSegment(entry.directoryPath),
        grandParentName: _lastSegment(_parentOf(entry.directoryPath)),
        date: spec.byCreated ? entry.created : entry.modified,
        index: index,
        counter: spec.counter,
      );

      // Порядок шагов — один на всё приложение и записан в спеке (§4).
      final newBase = spec.nameCase.apply(name.expand(subject));
      final newExtension = spec.extensionCase.apply(extension.expand(subject));
      final joined = newExtension.isEmpty ? newBase : '$newBase.$newExtension';
      final replaced = replacement.isEmpty ? joined : replacement.apply(joined);
      final to = trimmedFileName(replaced);

      proposed.add(to);
      if (to.isNotEmpty && to != entry.name) {
        final key = _keyOf(entry.directoryPath, to);
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    // Второй проход: признак строки виден только тогда, когда посчитаны все.
    final rows = <RenameRow>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final to = proposed[index];
      final key = _keyOf(entry.directoryPath, to);
      final occupied = taken[entry.directoryPath] ?? const <String>{};

      final RenameStatus status;
      if (to.isEmpty || to == entry.name) {
        status = RenameStatus.unchanged;
      } else if ((counts[key] ?? 0) > 1) {
        status = RenameStatus.duplicate;
      } else if (occupied.any((name) => name.toLowerCase() == to.toLowerCase()) && !leaving.contains(key)) {
        status = RenameStatus.taken;
      } else {
        status = RenameStatus.renamed;
      }
      rows.add(RenameRow(entry: entry, to: to, status: status));
    }
    return RenamePlan(List.unmodifiable(rows));
  }

  final List<RenameRow> rows;

  /// Сколько имён изменится.
  int get changes => rows.where((row) => row.status == RenameStatus.renamed).length;

  /// Сколько строк спорит.
  int get collisions => rows.where((row) => row.status.collides).length;

  bool get hasCollisions => collisions > 0;

  /// Пары «путь → новое имя» — то, что уедет работе. Только меняющиеся.
  Map<String, String> get renames => {
    for (final row in rows)
      if (row.status == RenameStatus.renamed) row.entry.path: row.to,
  };

  /// Ключ сравнения: каталог и имя **без учёта регистра** — на macOS его не
  /// различает и файловая система (§8).
  static String _keyOf(String directory, String name) => '$directory ${name.toLowerCase()}';

  static String _lastSegment(String path) {
    if (path.isEmpty) {
      return '';
    }
    final at = path.lastIndexOf('/');
    return at < 0 ? path : path.substring(at + 1);
  }

  static String _parentOf(String path) {
    final at = path.lastIndexOf('/');
    return at <= 0 ? '' : path.substring(0, at);
  }
}
