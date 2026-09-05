import 'dart:typed_data';

import 'package:fc_ui_api/fc_ui_api.dart';

import 'text_probe.dart';

/// Известные типы и то, чем их узнают.
///
/// Своя таблица, а не пакет: нужно полсотни форматов, а не полный реестр IANA,
/// и таблица должна лежать там же, где тесты на неё
/// (`docs/spec/content-types.md`, §8).
abstract final class ContentTypeTable {
  // --- Картинки ---
  static const png = ContentType('png', title: 'PNG image', group: ContentGroup.image);
  static const jpeg = ContentType('jpeg', title: 'JPEG image', group: ContentGroup.image);
  static const gif = ContentType('gif', title: 'GIF image', group: ContentGroup.image);
  static const webp = ContentType('webp', title: 'WebP image', group: ContentGroup.image);
  static const bmp = ContentType('bmp', title: 'BMP image', group: ContentGroup.image);
  static const tiff = ContentType('tiff', title: 'TIFF image', group: ContentGroup.image);
  static const ico = ContentType('ico', title: 'Windows icon', group: ContentGroup.image);
  static const icns = ContentType('icns', title: 'Apple icon image', group: ContentGroup.image);
  static const svg = ContentType('svg', title: 'SVG image', group: ContentGroup.image);

  // --- Архивы ---
  static const zip = ContentType('zip', title: 'Zip archive', group: ContentGroup.archive);
  static const gzip = ContentType('gzip', title: 'Gzip archive', group: ContentGroup.archive);
  static const bzip2 = ContentType('bzip2', title: 'Bzip2 archive', group: ContentGroup.archive);
  static const xz = ContentType('xz', title: 'XZ archive', group: ContentGroup.archive);
  static const zstd = ContentType('zstd', title: 'Zstandard archive', group: ContentGroup.archive);
  static const sevenZip = ContentType('7z', title: '7-Zip archive', group: ContentGroup.archive);
  static const tar = ContentType('tar', title: 'Tar archive', group: ContentGroup.archive);
  static const rar = ContentType('rar', title: 'RAR archive', group: ContentGroup.archive);
  static const ar = ContentType('ar', title: 'Unix archive', group: ContentGroup.archive);
  static const deb = ContentType('deb', title: 'Debian package', group: ContentGroup.archive);

  // --- Исполняемое ---
  static const machO = ContentType('mach-o', title: 'Mach-O executable', group: ContentGroup.executable);
  static const machOFat = ContentType('mach-o-fat', title: 'Mach-O universal binary', group: ContentGroup.executable);
  static const elf = ContentType('elf', title: 'ELF executable', group: ContentGroup.executable);
  static const pe = ContentType('pe', title: 'Windows executable', group: ContentGroup.executable);
  static const javaClass = ContentType('class', title: 'Java class', group: ContentGroup.executable);
  static const script = ContentType('script', title: 'Script', group: ContentGroup.executable);
  static const wasm = ContentType('wasm', title: 'WebAssembly module', group: ContentGroup.executable);

  // --- Документы ---
  static const pdf = ContentType('pdf', title: 'PDF document', group: ContentGroup.document);
  static const rtf = ContentType('rtf', title: 'RTF document', group: ContentGroup.document);
  static const postscript = ContentType('postscript', title: 'PostScript document', group: ContentGroup.document);
  static const plist = ContentType('plist', title: 'Binary property list', group: ContentGroup.document);
  static const sqlite = ContentType('sqlite', title: 'SQLite database', group: ContentGroup.document);
  static const dicom = ContentType('dicom', title: 'DICOM image', group: ContentGroup.document);

  // --- Звук и видео ---
  static const mp3 = ContentType('mp3', title: 'MP3 audio', group: ContentGroup.audio);
  static const ogg = ContentType('ogg', title: 'Ogg audio', group: ContentGroup.audio);
  static const flac = ContentType('flac', title: 'FLAC audio', group: ContentGroup.audio);
  static const wav = ContentType('wav', title: 'WAV audio', group: ContentGroup.audio);
  static const midi = ContentType('midi', title: 'MIDI', group: ContentGroup.audio);
  static const mp4 = ContentType('mp4', title: 'MP4 video', group: ContentGroup.video);
  static const mov = ContentType('mov', title: 'QuickTime video', group: ContentGroup.video);
  static const avi = ContentType('avi', title: 'AVI video', group: ContentGroup.video);
  static const matroska = ContentType('matroska', title: 'Matroska video', group: ContentGroup.video);

  // --- Шрифты ---
  static const ttf = ContentType('ttf', title: 'TrueType font', group: ContentGroup.font);
  static const otf = ContentType('otf', title: 'OpenType font', group: ContentGroup.font);
  static const woff = ContentType('woff', title: 'WOFF font', group: ContentGroup.font);
  static const woff2 = ContentType('woff2', title: 'WOFF2 font', group: ContentGroup.font);

  // --- Остальное ---
  static const text = ContentType('text', title: 'Text', group: ContentGroup.text);

  /// Ничего не совпало — и это **ответ**: см. [ContentGroup.binary].
  static const binary = ContentType('binary', title: 'Binary', group: ContentGroup.binary);

  /// Все типы таблицы — тестам и будущей колонке.
  static const List<ContentType> all = [
    png,
    jpeg,
    gif,
    webp,
    bmp,
    tiff,
    ico,
    icns,
    svg,
    zip,
    gzip,
    bzip2,
    xz,
    zstd,
    sevenZip,
    tar,
    rar,
    ar,
    deb,
    machO,
    machOFat,
    elf,
    pe,
    javaClass,
    script,
    wasm,
    pdf,
    rtf,
    postscript,
    plist,
    sqlite,
    dicom,
    mp3,
    ogg,
    flac,
    wav,
    midi,
    mp4,
    mov,
    avi,
    matroska,
    ttf,
    otf,
    woff,
    woff2,
    text,
    binary,
  ];

  /// Сколько байт от начала читать.
  ///
  /// Хватает всем сигнатурам — самые дальние стоят на 257 (`tar`) и 128
  /// (`dicom`) — и эвристике текста, которая смотрит на те же байты.
  static const int headSize = 4096;

  /// Тип по началу файла.
  ///
  /// Порядок разбора: сперва случаи, где одних байтов мало (§8 спеки), потом
  /// таблица, потом эвристика «текст или двоичное» (§9). Пустое начало —
  /// [binary]: у пустого файла это и есть ответ.
  static ContentType of(Uint8List head) {
    if (head.isEmpty) {
      return binary;
    }
    return _special(head) ?? _table(head) ?? textOrBinary(head);
  }

  /// Случаи, где одной сигнатуры мало.
  static ContentType? _special(Uint8List head) {
    // `CA FE BA BE` — это и Java-класс, и толстый Mach-O. Различает следующее
    // слово: у класса это версия (major 43…80, minor 0 или 65535 у preview), у
    // толстого двоичного — число архитектур, а восемнадцати тысяч их не
    // бывает. Не подошло ни то ни другое — пусть решают дальше.
    if (_at(head, 0, const [0xca, 0xfe, 0xba, 0xbe])) {
      final word = _be32(head, 4);
      if (word == null) {
        return null;
      }
      final major = word & 0xffff;
      final minor = word >> 16;
      if ((minor == 0 || minor == 0xffff) && major >= 43 && major <= 80) {
        return javaClass;
      }
      return word >= 1 && word <= 20 ? machOFat : null;
    }

    // `RIFF` — это семья, а что именно, написано со смещения 8.
    if (_at(head, 0, _ascii('RIFF'))) {
      if (_at(head, 8, _ascii('WEBP'))) {
        return webp;
      }
      if (_at(head, 8, _ascii('WAVE'))) {
        return wav;
      }
      if (_at(head, 8, _ascii('AVI '))) {
        return avi;
      }
      return null;
    }

    // `ftyp` стоит со смещения 4, а марка — со смещения 8.
    if (_at(head, 4, _ascii('ftyp'))) {
      return _at(head, 8, _ascii('qt  ')) ? mov : mp4;
    }

    // `!<arch>` — обычный архив `ar`; `deb` отличает `debian-binary` следом.
    if (_at(head, 0, _ascii('!<arch>\n'))) {
      return _at(head, 8, _ascii('debian-binary')) ? deb : ar;
    }

    return null;
  }

  /// Простые сигнатуры: байты на известном месте.
  static ContentType? _table(Uint8List head) {
    for (final signature in signatures) {
      if (_at(head, signature.at, signature.bytes)) {
        return signature.type;
      }
    }
    return null;
  }

  /// Порядок — от длинного к короткому: короткая сигнатура, стоящая раньше
  /// длинной, съела бы её.
  ///
  /// Открыт не для чтения снаружи, а для теста: он и следит за этим порядком.
  /// Глазами такое не удержать — таблица растёт, а `MZ` из двух байт стоит в
  /// ней рядом с восьмибайтовым `PNG`.
  static final List<ContentSignature> signatures = [
    ContentSignature(png, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    ContentSignature(sqlite, _ascii('SQLite format 3\x00')),
    ContentSignature(plist, _ascii('bplist00')),
    ContentSignature(xz, const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]),
    ContentSignature(sevenZip, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]),
    ContentSignature(rar, _ascii('Rar!\x1a\x07')),
    ContentSignature(rtf, _ascii('{\\rtf')),
    ContentSignature(tar, _ascii('ustar'), at: 257),
    // Все три подписи `zip`: пустой архив начинается с записи конца каталога,
    // а не с локального заголовка — `zip_index.dart` знает столько же.
    ContentSignature(zip, _ascii('PK\x03\x04')),
    ContentSignature(zip, _ascii('PK\x05\x06')),
    ContentSignature(zip, _ascii('PK\x07\x08')),
    ContentSignature(dicom, _ascii('DICM'), at: 128),
    ContentSignature(machO, const [0xfe, 0xed, 0xfa, 0xce]),
    ContentSignature(machO, const [0xfe, 0xed, 0xfa, 0xcf]),
    ContentSignature(machO, const [0xce, 0xfa, 0xed, 0xfe]),
    ContentSignature(machO, const [0xcf, 0xfa, 0xed, 0xfe]),
    ContentSignature(machOFat, const [0xbe, 0xba, 0xfe, 0xca]),
    ContentSignature(machOFat, const [0xca, 0xfe, 0xba, 0xbf]),
    ContentSignature(elf, const [0x7f, 0x45, 0x4c, 0x46]),
    ContentSignature(wasm, const [0x00, 0x61, 0x73, 0x6d]),
    ContentSignature(matroska, const [0x1a, 0x45, 0xdf, 0xa3]),
    ContentSignature(woff2, _ascii('wOF2')),
    ContentSignature(woff, _ascii('wOFF')),
    ContentSignature(otf, _ascii('OTTO')),
    ContentSignature(ttf, const [0x00, 0x01, 0x00, 0x00]),
    ContentSignature(ttf, _ascii('true')),
    ContentSignature(icns, _ascii('icns')),
    ContentSignature(ico, const [0x00, 0x00, 0x01, 0x00]),
    ContentSignature(ogg, _ascii('OggS')),
    ContentSignature(flac, _ascii('fLaC')),
    ContentSignature(midi, _ascii('MThd')),
    ContentSignature(zstd, const [0x28, 0xb5, 0x2f, 0xfd]),
    ContentSignature(gif, _ascii('GIF8')),
    ContentSignature(pdf, _ascii('%PDF')),
    ContentSignature(postscript, _ascii('%!PS')),
    ContentSignature(tiff, const [0x49, 0x49, 0x2a, 0x00]),
    ContentSignature(tiff, const [0x4d, 0x4d, 0x00, 0x2a]),
    ContentSignature(jpeg, const [0xff, 0xd8, 0xff]),
    ContentSignature(mp3, _ascii('ID3')),
    ContentSignature(mp3, const [0xff, 0xfb]),
    ContentSignature(mp3, const [0xff, 0xf3]),
    ContentSignature(mp3, const [0xff, 0xf2]),
    ContentSignature(bzip2, _ascii('BZh')),
    ContentSignature(gzip, const [0x1f, 0x8b]),
    ContentSignature(pe, _ascii('MZ')),
    ContentSignature(bmp, _ascii('BM')),
    // `#!` — самая короткая и самая слабая, поэтому последней.
    ContentSignature(script, _ascii('#!')),
  ];

  static bool _at(Uint8List head, int at, List<int> bytes) {
    if (head.length < at + bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (head[at + i] != bytes[i]) {
        return false;
      }
    }
    return true;
  }

  static int? _be32(Uint8List head, int at) {
    if (head.length < at + 4) {
      return null;
    }
    return (head[at] << 24) | (head[at + 1] << 16) | (head[at + 2] << 8) | head[at + 3];
  }

  static List<int> _ascii(String value) => value.codeUnits;
}

/// Одна строка таблицы: байты, которые должны стоять на [at].
class ContentSignature {
  ContentSignature(this.type, this.bytes, {this.at = 0});

  final ContentType type;
  final List<int> bytes;

  /// Смещение, на котором стоит подпись: у `tar` это 257, у `dicom` — 128.
  final int at;
}
