import 'dart:convert';

/// Правила кодирования S3 — их пять, и смешивать их нельзя
/// (`docs/spec/s3.md`, §10). Именно здесь их обычно и путают: ключ в адресе
/// запроса и значение в строке запроса кодируются по-разному, а листинг
/// приезжает закодированным третьим способом.

/// Незакодированные знаки — те, что SigV4 называет «unreserved».
bool _unreserved(int byte) =>
    (byte >= 0x41 && byte <= 0x5A) || // A–Z
    (byte >= 0x61 && byte <= 0x7A) || // a–z
    (byte >= 0x30 && byte <= 0x39) || // 0–9
    byte == 0x2D || // -
    byte == 0x5F || // _
    byte == 0x2E || // .
    byte == 0x7E; // ~

/// Кодирование SigV4: UTF-8 побайтно, всё кроме «unreserved» — `%XX` заглавными.
///
/// [keepSlash] — оставить `/` как есть: так кодируется путь (правило 1). В
/// значении запроса `/` кодируется тоже (правило 2).
String uriEncode(String value, {bool keepSlash = false}) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (_unreserved(byte) || (keepSlash && byte == 0x2F)) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

/// Правило 1: путь запроса — корзина и ключ, посегментно; `/` между сегментами
/// остаётся. Тот же текст уходит и в провод, и в каноническую строку подписи:
/// S3 не нормализует путь и не кодирует его дважды — в отличие от общего SigV4.
///
/// `a b/+%/ж` → `a%20b/%2B%25/%D0%B6`.
String encodeKeyPath(String path) => uriEncode(path, keepSlash: true);

/// Правило 2: строка запроса — ключи и значения закодированы целиком (и `/`
/// тоже), пары упорядочены по закодированному ключу, затем по значению; ключ
/// без значения — `k=`. Этот текст тоже одинаков в проводе и в подписи.
String canonicalQuery(Map<String, String> query) {
  final pairs = [for (final entry in query.entries) (uriEncode(entry.key), uriEncode(entry.value))]..sort((a, b) {
    final byKey = a.$1.compareTo(b.$1);
    return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
  });
  return pairs.map((pair) => '${pair.$1}=${pair.$2}').join('&');
}

/// Правило 3: источник копии — `/корзина/ключ` по правилу пути.
String copySource(String bucket, String key) => '/${encodeKeyPath('$bucket/$key')}';

/// Правило 4: значения из листинга с `encoding-type=url` — раскодировать как
/// форму: `+` — пробел, `%2B` — плюс.
///
/// Только когда ответ сказал `<EncodingType>url</EncodingType>`: иначе ключ
/// приехал сырым, и плюс в нём — настоящий плюс.
String decodeListingValue(String value) => Uri.decodeQueryComponent(value);

/// Можно ли отправить ключ, не потеряв его по дороге.
///
/// `Uri` в Dart выбрасывает из пути сегменты `.` и `..` — такой ключ ушёл бы
/// чужим. Пустой сегмент (`a//b`) уходит как есть, но строки у него в панели
/// нет: имя пустое.
bool sendableKey(String key) => !key.split('/').any((segment) => segment == '.' || segment == '..');
