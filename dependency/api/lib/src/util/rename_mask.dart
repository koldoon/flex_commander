/// Маска переименования: `[N]_[C].[E]`.
///
/// Написана как в Multi-Rename Tool из Total Commander — человек, пришедший
/// оттуда, ничего не переучивает (`docs/spec/multi-rename.md`, §3).
///
/// Живёт рядом с [FileMask] и по той же причине: это разбор **текста имени**,
/// без файловой системы, без служб и без виджетов. Имена считает экран и он же
/// отдаёт их работе готовыми — ядро масок не знает вовсе (§2).
library;

/// Что маска умеет спросить об объекте.
///
/// Всё, кроме номера: номер маска считает сама по месту строки ([index]) —
/// иначе пересчёт предпросмотра на каждое нажатие начинался бы с того места,
/// где кончился прошлый (§5).
class RenameSubject {
  const RenameSubject({
    required this.base,
    required this.extension,
    this.parentName = '',
    this.grandParentName = '',
    this.date,
    this.index = 0,
    this.counter = const RenameCounter(),
  });

  /// Основа и расширение — уже разделённые службой `FileNaming`: составные
  /// расширения (`архив.tar.gz`) разбирает она, а не маска (§4).
  final String base;
  final String extension;

  /// Имя каталога, в котором объект лежит, и имя каталога над ним.
  final String parentName;
  final String grandParentName;

  /// Дата объекта; null — неизвестна, и `[Y]`, `[M]`… дают пустоту.
  final DateTime? date;

  /// Место строки в списке, с нуля. По нему и считается номер.
  final int index;

  /// Счётчик по полям окна; `[C10+5:3]` в самой маске его перебивает.
  final RenameCounter counter;
}

/// Счётчик: с чего, шаг и сколько разрядов.
class RenameCounter {
  const RenameCounter({this.start = 1, this.step = 1, this.digits = 1});

  final int start;
  final int step;
  final int digits;

  String at(int index) => (start + step * index).toString().padLeft(digits, '0');

  RenameCounter copyWith({int? start, int? step, int? digits}) =>
      RenameCounter(start: start ?? this.start, step: step ?? this.step, digits: digits ?? this.digits);
}

/// Разобранная маска переименования.
class RenameMask {
  const RenameMask._(this.text, this._parts, this.problem);

  /// Разобрать набранное.
  ///
  /// **Не бросает**: негодная маска просто получается негодной ([isValid]), а
  /// окно показывает [problem] у поля — тем же приёмом, что `NameRule` у
  /// поиска. Бросать здесь значило бы разбирать набранное на каждую букву
  /// внутри `try`.
  factory RenameMask.parse(String text) {
    final parts = <_Part>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        parts.add(_Literal(buffer.toString()));
        buffer.clear();
      }
    }

    for (var at = 0; at < text.length; at++) {
      final char = text[at];
      if (char != '[') {
        buffer.write(char);
        continue;
      }
      // `[[` — сама скобка: без этого её в имя не поставить вовсе.
      if (at + 1 < text.length && text[at + 1] == '[') {
        buffer.write('[');
        at++;
        continue;
      }
      final close = text.indexOf(']', at + 1);
      if (close < 0) {
        // Недописанная скобка — ошибка, а не текст: иначе `[N2-5` молча
        // переименует сорок файлов в «[N2-5» (§3).
        return RenameMask._(text, const [], 'Незакрытая «[»');
      }
      final token = text.substring(at + 1, close);
      final part = _tokenOf(token);
      if (part == null) {
        return RenameMask._(text, const [], 'Непонятная запись «[$token]»');
      }
      flush();
      parts.add(part);
      at = close;
    }
    flush();
    return RenameMask._(text, List.unmodifiable(parts), null);
  }

  /// Что набрано — как набрано: то же значение возвращается в поле и уходит в
  /// сохранённый набор.
  final String text;

  final List<_Part> _parts;

  /// Что именно не понято; null — маска годная.
  final String? problem;

  bool get isValid => problem == null;

  /// Поля модулей (`[=id.поле]`), которые маска попросила.
  ///
  /// Грамматика занята с первого дня, провайдеров пока нет: такие записи
  /// разворачиваются в пустоту, а кто их подставит — отдельный этап (§11).
  Set<String> get fields => {
    for (final part in _parts)
      if (part is _Field) part.name,
  };

  /// Развернуть маску для этого объекта.
  String expand(RenameSubject subject) {
    if (!isValid) {
      return '';
    }
    final out = StringBuffer();
    for (final part in _parts) {
      out.write(part.expand(subject));
    }
    return out.toString();
  }

  @override
  String toString() => 'RenameMask("$text")';
}

/// Кусок разобранной маски.
sealed class _Part {
  const _Part();

  String expand(RenameSubject subject);
}

class _Literal extends _Part {
  const _Literal(this.text);

  final String text;

  @override
  String expand(RenameSubject subject) => text;
}

/// Срез основы или расширения: `[N]`, `[N2-5]`, `[N-3]`.
class _Slice extends _Part {
  const _Slice({required this.ofBase, this.from, this.to, this.count, this.toEnd = false});

  final bool ofBase;

  /// Границы — **как их пишет человек**: с единицы, отрицательные считают с
  /// конца. Перевод в места строки делает [expand], и только он.
  final int? from;
  final int? to;
  final int? count;

  /// `[N3-]` — с третьего до конца. Отдельным признаком, а не отсутствием
  /// [to]: у одного знака (`[N5]`) поля ровно те же, и различить их нечем.
  final bool toEnd;

  @override
  String expand(RenameSubject subject) {
    final source = ofBase ? subject.base : subject.extension;
    if (from == null) {
      return source;
    }
    final start = _placeOf(from!, source.length);
    if (start < 0 || start >= source.length) {
      // Срез за краем строки — пустота, а не ошибка: `[N1-8]` на коротком
      // имени обычное дело (§3).
      return '';
    }
    final int end;
    if (count != null) {
      end = start + count!;
    } else if (to != null) {
      end = _placeOf(to!, source.length) + 1;
    } else if (toEnd) {
      end = source.length;
    } else {
      end = start + 1;
    }
    if (end <= start) {
      return '';
    }
    return source.substring(start, end > source.length ? source.length : end);
  }

  /// Место в строке по тому, как его написал человек: с единицы, `-1` — последний.
  static int _placeOf(int written, int length) => written < 0 ? length + written : written - 1;
}

/// Счётчик: `[C]`, `[C10+5:3]`.
class _Counter extends _Part {
  const _Counter({this.start, this.step, this.digits});

  final int? start;
  final int? step;
  final int? digits;

  @override
  String expand(RenameSubject subject) {
    final counter = RenameCounter(
      start: start ?? subject.counter.start,
      step: step ?? subject.counter.step,
      digits: digits ?? subject.counter.digits,
    );
    return counter.at(subject.index);
  }
}

/// Часть даты: `[Y]`, `[M]`, `[D]`, `[h]`, `[m]`, `[s]`.
class _DatePart extends _Part {
  const _DatePart(this.letter);

  final String letter;

  @override
  String expand(RenameSubject subject) {
    final date = subject.date;
    if (date == null) {
      return '';
    }
    return switch (letter) {
      'Y' => date.year.toString().padLeft(4, '0'),
      'M' => date.month.toString().padLeft(2, '0'),
      'D' => date.day.toString().padLeft(2, '0'),
      'h' => date.hour.toString().padLeft(2, '0'),
      'm' => date.minute.toString().padLeft(2, '0'),
      _ => date.second.toString().padLeft(2, '0'),
    };
  }
}

/// Имя каталога: `[P]` — родительского, `[G]` — деда.
class _Folder extends _Part {
  const _Folder({required this.grand});

  final bool grand;

  @override
  String expand(RenameSubject subject) => grand ? subject.grandParentName : subject.parentName;
}

/// Поле модуля: `[=id.поле]`. Грамматика занята, подставлять пока нечем.
class _Field extends _Part {
  const _Field(this.name);

  final String name;

  @override
  String expand(RenameSubject subject) => '';
}

final RegExp _single = RegExp(r'^(-?\d+)$');
final RegExp _range = RegExp(r'^(-?\d+)-(-?\d+)?$');
final RegExp _count = RegExp(r'^(-?\d+),(\d+)$');
final RegExp _counterArgs = RegExp(r'^(\d+)?(?:\+(\d+))?(?::(\d+))?$');

/// Разбирает содержимое скобок; null — такого мы не знаем.
_Part? _tokenOf(String token) {
  if (token.isEmpty) {
    return null;
  }
  if (token.startsWith('=')) {
    final name = token.substring(1);
    return name.isEmpty ? null : _Field(name);
  }
  final letter = token[0];
  final rest = token.substring(1);

  switch (letter) {
    case 'N' || 'E':
      return _sliceOf(ofBase: letter == 'N', argument: rest);
    case 'C':
      final args = _counterArgs.firstMatch(rest);
      if (rest.isNotEmpty && args == null) {
        return null;
      }
      return _Counter(
        start: args == null ? null : int.tryParse(args.group(1) ?? ''),
        step: args == null ? null : int.tryParse(args.group(2) ?? ''),
        digits: args == null ? null : int.tryParse(args.group(3) ?? ''),
      );
    case 'Y' || 'M' || 'D' || 'h' || 'm' || 's':
      return rest.isEmpty ? _DatePart(letter) : null;
    case 'P' || 'G':
      return rest.isEmpty ? _Folder(grand: letter == 'G') : null;
    default:
      return null;
  }
}

_Part? _sliceOf({required bool ofBase, required String argument}) {
  if (argument.isEmpty) {
    return _Slice(ofBase: ofBase);
  }
  if (_single.hasMatch(argument)) {
    return _Slice(ofBase: ofBase, from: int.parse(argument));
  }
  if (_count.firstMatch(argument) case final match?) {
    return _Slice(ofBase: ofBase, from: int.parse(match.group(1)!), count: int.parse(match.group(2)!));
  }
  if (_range.firstMatch(argument) case final match?) {
    final to = match.group(2);
    return _Slice(
      ofBase: ofBase,
      from: int.parse(match.group(1)!),
      to: to == null ? null : int.parse(to),
      toEnd: to == null,
    );
  }
  return null;
}
