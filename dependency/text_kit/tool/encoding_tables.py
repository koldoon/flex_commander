#!/usr/bin/env python3
"""Выписывает верхние половины однобайтовых таблиц из codecs Python.

Запуск из пакета: python3 tool/encoding_tables.py > lib/src/encoding_tables.dart
(docs/spec/text-encodings.md, §2). Дыра в таблице — U+FFFF.
"""

TABLES = [
    ('windows1251', 'cp1251'),
    ('koi8r', 'koi8_r'),
    ('koi8u', 'koi8_u'),
    ('cp866', 'cp866'),
    ('macCyrillic', 'mac_cyrillic'),
    ('iso88595', 'iso8859_5'),
    ('windows1252', 'cp1252'),
]

print('// Создано tool/encoding_tables.py из таблиц Python — руками не править.')
print('//')
print('// Верхняя половина каждой однобайтовой кодировки: знак для байтов 0x80–0xFF,')
print('// U+FFFF — дыра в таблице (`docs/spec/text-encodings.md`, §2).')
print()
print('const Map<String, String> encodingTables = {')
for name, codec in TABLES:
    chars = []
    for byte in range(128, 256):
        try:
            chars.append(ord(bytes([byte]).decode(codec)))
        except UnicodeDecodeError:
            chars.append(0xFFFF)
    print(f"  '{name}':")
    for row in range(0, 128, 16):
        body = ''.join(f'\\u{c:04X}' for c in chars[row:row + 16])
        end = ',' if row == 112 else ''
        print(f"      '{body}'{end}")
print('};')
