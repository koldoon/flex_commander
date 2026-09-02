/// Сравнение строк «по-человечески»: без учёта регистра и с числами как
/// числами, чтобы `file2` шёл перед `file10`.
///
/// Работает по кодам символов, не выделяя ни одной строки: сравнение зовётся
/// на каждую пару при сортировке, и десять тысяч имён дают около четверти
/// миллиона вызовов. Прежняя запись приводила обе строки к нижнему регистру
/// **внутри** сравнения и разбирала числа регулярным выражением — на десяти
/// тысячах записей сортировка стоила дороже самого чтения каталога.
int naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;

  while (i < a.length && j < b.length) {
    final charA = a.codeUnitAt(i);
    final charB = b.codeUnitAt(j);

    if (_isDigit(charA) && _isDigit(charB)) {
      var endA = i;
      var endB = j;
      while (endA < a.length && _isDigit(a.codeUnitAt(endA))) {
        endA++;
      }
      while (endB < b.length && _isDigit(b.codeUnitAt(endB))) {
        endB++;
      }

      final result = _compareNumbers(a, i, endA, b, j, endB);
      if (result != 0) {
        return result;
      }
      i = endA;
      j = endB;
      continue;
    }

    if (charA != charB) {
      // Регистр приводится только у разошедшихся символов: у совпавших он и
      // так одинаков, а приводить всю строку — значит выделять её заново.
      final lowerA = _toLower(charA);
      final lowerB = _toLower(charB);
      if (lowerA != lowerB) {
        return lowerA < lowerB ? -1 : 1;
      }
    }
    i++;
    j++;
  }

  final rest = (a.length - i).compareTo(b.length - j);
  if (rest != 0) {
    return rest;
  }
  // Строки различаются только регистром: сравниваем как есть, чтобы порядок
  // оставался устойчивым.
  return a.compareTo(b);
}

/// Нижний регистр одного символа.
///
/// Латиница, кириллица и латиница-1 разобраны сдвигом — это те буквы, что
/// встречаются в именах файлов постоянно. Всё остальное уходит в `toLowerCase`
/// по одному символу: путь редкий, и выделение строки там не жалко.
int _toLower(int unit) {
  if (unit >= 0x41 && unit <= 0x5A) {
    return unit + 0x20; // A–Z
  }
  if (unit < 0x80) {
    return unit;
  }
  if (unit >= 0x410 && unit <= 0x42F) {
    return unit + 0x20; // А–Я
  }
  if (unit == 0x401) {
    return 0x451; // Ё
  }
  if (unit >= 0xC0 && unit <= 0xDE && unit != 0xD7) {
    return unit + 0x20; // À–Þ, кроме знака умножения
  }
  final lower = String.fromCharCode(unit).toLowerCase();
  return lower.isEmpty ? unit : lower.codeUnitAt(0);
}

/// Числа сравниваются по значению, ведущие нули не важны; при равенстве
/// короче — раньше, поэтому `file01` и `file1` не считаются одинаковыми.
///
/// Границами, а не подстроками: вырезать куски ради сравнения значило бы
/// выделять по две строки на каждое число в каждом сравнении.
int _compareNumbers(String a, int startA, int endA, String b, int startB, int endB) {
  var i = startA;
  var j = startB;

  // Ведущие нули ничего не значат — кроме случая, когда всё число из нулей.
  while (i < endA - 1 && a.codeUnitAt(i) == _zeroCode) {
    i++;
  }
  while (j < endB - 1 && b.codeUnitAt(j) == _zeroCode) {
    j++;
  }

  final lengthA = endA - i;
  final lengthB = endB - j;
  if (lengthA != lengthB) {
    return lengthA < lengthB ? -1 : 1;
  }

  while (i < endA) {
    final charA = a.codeUnitAt(i);
    final charB = b.codeUnitAt(j);
    if (charA != charB) {
      return charA < charB ? -1 : 1;
    }
    i++;
    j++;
  }

  // Значения равны: короче исходная запись — раньше.
  return (endA - startA).compareTo(endB - startB);
}

const int _zeroCode = 0x30;

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
