/// Запись оглавления архива: то, что о ней известно без распаковки.
///
/// Каталоги в 7z, как и в zip, — не обязательные записи: `a/b.txt` может лежать
/// в архиве, где никакого `a` нет вовсе. Недостающие достраиваются по путям, и
/// у достроенного нет ни даты, ни прав.
class SevenZipEntry {
  SevenZipEntry.file({
    required this.name,
    required this.entryName,
    required this.size,
    this.modified,
    this.mode = 0,
    this.encrypted = false,
  }) : isDirectory = false;

  SevenZipEntry.directory({required this.name, this.entryName = '', this.modified, this.mode = 0})
    : isDirectory = true,
      size = 0,
      encrypted = false;

  /// Имя внутри родительского каталога.
  final String name;

  /// Полное имя записи в архиве — им её и просят у программы.
  final String entryName;

  final bool isDirectory;
  final int size;
  final DateTime? modified;

  /// Права доступа; 0 — архив собран там, где их не бывает (Windows).
  final int mode;

  /// Содержимое зашифровано. Прочитать его без пароля нельзя, и узнать об этом
  /// лучше до распаковки, а не по невнятной ошибке программы.
  final bool encrypted;

  final Map<String, SevenZipEntry> children = {};

  @override
  String toString() => entryName.isEmpty ? name : entryName;
}

/// Оглавление архива деревом.
class SevenZipListing {
  SevenZipListing(this.root);

  final SevenZipEntry root;

  /// Запись по разобранному на части пути; null — такой в архиве нет.
  SevenZipEntry? at(List<String> segments) {
    var entry = root;
    for (final name in segments) {
      final child = entry.children[name];
      if (child == null) {
        return null;
      }
      entry = child;
    }
    return entry;
  }
}

/// Разбирает вывод `7z l -slt`.
///
/// Формат — блоки `ключ = значение`, разделённые пустой строкой. Разбор
/// намеренно защитный: перед записями программа печатает шапку со своей
/// версией и свойствами архива, и шапка эта у разных сборок разная. Записи
/// начинаются после строки из дефисов; блок без `Path` и блок со свойствами
/// самого архива (у него есть `Type`, но нет ни размера, ни прав)
/// пропускаются — так разбор переживает и лишнюю шапку, и её отсутствие.
SevenZipListing parseSevenZipListing(String output) {
  final root = SevenZipEntry.directory(name: '/');
  final blocks = _blocks(output).toList();

  // Записи начинаются после строки из дефисов. Если её нет вовсе — читаем всё
  // подряд: вывод мог прийти без шапки, и терять из-за этого весь архив нельзя.
  var started = !blocks.any((block) => block.separated);

  for (final block in blocks) {
    if (!started) {
      started = block.separated;
      if (!started) {
        continue;
      }
    }

    final path = block.fields['Path'];
    if (path == null || path.isEmpty) {
      continue;
    }
    if (block.fields.containsKey('Type') && !block.fields.containsKey('Attributes')) {
      // Свойства самого архива, а не запись в нём.
      continue;
    }

    final segments = path.split(RegExp(r'[/\\]')).where((name) => name.isNotEmpty && name != '.').toList();
    if (segments.isEmpty) {
      continue;
    }

    final attributes = block.fields['Attributes'] ?? '';
    final isDirectory = block.fields['Folder'] == '+' || _flagsOf(attributes).contains('D');
    final mode = _modeOf(attributes);
    final modified = _dateOf(block.fields['Modified']);

    var parent = root;
    for (final name in segments.take(segments.length - 1)) {
      parent = parent.children.putIfAbsent(name, () => SevenZipEntry.directory(name: name));
    }

    final name = segments.last;
    if (isDirectory) {
      // Каталог мог быть уже достроен по пути соседа — тогда у него нет ни
      // даты, ни прав, и запись их приносит. Свои дети при этом остаются.
      final existing = parent.children[name];
      final replacement = SevenZipEntry.directory(name: name, entryName: path, modified: modified, mode: mode);
      if (existing != null) {
        replacement.children.addAll(existing.children);
      }
      parent.children[name] = replacement;
      continue;
    }

    // Одноимённая запись в архиве бывает: побеждает последняя, как при
    // распаковке.
    parent.children[name] = SevenZipEntry.file(
      name: name,
      entryName: path,
      size: int.tryParse(block.fields['Size'] ?? '') ?? 0,
      modified: modified,
      mode: mode,
      encrypted: block.fields['Encrypted'] == '+',
    );
  }

  return SevenZipListing(root);
}

/// Блок вывода: пары «ключ = значение» и признак того, что перед ним стояла
/// строка-разделитель.
class _Block {
  _Block(this.fields, {required this.separated});

  final Map<String, String> fields;
  final bool separated;
}

Iterable<_Block> _blocks(String output) sync* {
  var fields = <String, String>{};
  var separated = false;

  // Перевод строки бывает и с возвратом каретки: архив мог быть собран на
  // Windows, а вывод пройти через что угодно.
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    final isSeparator = RegExp(r'^-{5,}$').hasMatch(trimmed);

    if (trimmed.isEmpty || isSeparator) {
      // Разделитель тоже закрывает блок: пустой строки перед ним может и не
      // оказаться, а слипшиеся блоки — это перепутанные поля.
      if (fields.isNotEmpty) {
        yield _Block(fields, separated: separated);
        fields = <String, String>{};
      }
      separated = isSeparator;
      continue;
    }

    final split = trimmed.indexOf(' = ');
    if (split > 0) {
      fields[trimmed.substring(0, split)] = trimmed.substring(split + 3).trim();
    } else if (trimmed.endsWith(' =')) {
      // Пустое значение печатается без пробела после знака.
      fields[trimmed.substring(0, trimmed.length - 2)] = '';
    }
  }

  if (fields.isNotEmpty) {
    yield _Block(fields, separated: separated);
  }
}

/// Буквы признаков из `Attributes`: `D_ drwxr-xr-x` → `D_`.
String _flagsOf(String attributes) => attributes.split(' ').first;

/// Права из хвоста `Attributes` — `drwxr-xr-x`. 0, если их там нет: архив
/// собран на Windows, и прав в нём не было вовсе.
int _modeOf(String attributes) {
  final unix = attributes.split(' ').where((part) => RegExp(r'^[dl-][rwxsStT-]{9}$').hasMatch(part));
  if (unix.isEmpty) {
    return 0;
  }

  final rwx = unix.first.substring(1);
  var mode = 0;
  for (var i = 0; i < 9; i++) {
    mode <<= 1;
    if (rwx[i] != '-') {
      mode |= 1;
    }
  }
  return mode;
}

/// `2026-08-19 10:01:02` — местное время, как его печатает программа.
DateTime? _dateOf(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  // Хвост с долями секунды программа печатает не везде; разбирается голова.
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(value);
  if (match == null) {
    return null;
  }
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
