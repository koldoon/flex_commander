import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';

/// Каким переводом строки написан файл.
///
/// Помнить обязательно: разбор приводит всё к `\n`, и сохранение без этой
/// памяти молча превратило бы windows-файл в unix. Такую правку человек не
/// заказывал и заметит её не сразу — по чужому diff'у на весь файл.
enum LineBreak {
  lf('\n'),
  crlf('\r\n'),
  cr('\r');

  const LineBreak(this.text);

  final String text;

  /// Какой перевод в этом тексте: смотрим первый встреченный.
  ///
  /// Первый, а не большинство: смешанные файлы бывают, и «исправлять» их
  /// молча — то же самое самоуправство.
  static LineBreak detect(String text) {
    final index = text.indexOf('\n');
    if (index < 0) {
      return text.contains('\r') ? cr : lf;
    }
    return index > 0 && text.codeUnitAt(index - 1) == 0x0D ? crlf : lf;
  }
}

/// Текстовый файл, открытый на правку.
class TextFile {
  const TextFile({
    required this.text,
    required this.lineBreak,
    this.encoding = TextEncoding.utf8,
    this.bom = false,
    this.source = const [],
  });

  /// Прочесть байты на правку — строго: null, если в этой кодировке (или ни в
  /// одной, когда её не назвали) байты не читаются без потерь
  /// (`docs/spec/text-encodings.md`, §5).
  static TextFile? decode(List<int> bytes, {TextEncoding? as}) {
    final read = EncodedText.read(bytes, as: as, strict: true);
    if (read == null) {
      return null;
    }
    return TextFile(
      text: read.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      lineBreak: LineBreak.detect(read.text),
      encoding: read.encoding,
      bom: read.bom,
      source: bytes,
    );
  }

  /// Содержимое с переводами строк, приведёнными к `\n`.
  final String text;

  /// Каким переводом строки файл был записан.
  final LineBreak lineBreak;

  /// В какой кодировке он записан и была ли метка порядка байтов.
  final TextEncoding encoding;
  final bool bom;

  /// Байты, из которых прочитан: другая кодировка перечитывает их (§4).
  final List<int> source;

  /// Содержимое в том виде, в каком его надо записать обратно.
  String get bytes => lineBreak == LineBreak.lf ? text : text.replaceAll('\n', lineBreak.text);

  /// Читает файл, отказываясь от того, что правкой испортишь.
  ///
  /// **Работа, а не голое чтение**: файл может лежать на сервере, и тогда между
  /// нажатием `F4` и появлением редактора проходят секунды. Человеку нужно и
  /// видеть, что идёт чтение, и уметь его бросить, — а для того и другого нужна
  /// [Operation]. Кто её ведёт и кому показывает, решает вызывающий: панель
  /// берёт её себе (`Session.runWork`).
  ///
  /// Кодировка определяется по содержимому (`docs/spec/text-encodings.md`,
  /// §3) и проверяется **строго**, в отличие от просмотрщика: тот заменяет
  /// битые байты знаком замены, и это честно — он показывает. Сохранить такой
  /// текст обратно значило бы записать знаки замены вместо исходных байтов, то
  /// есть испортить файл молча.
  static Operation<FileEntry, TextFile> reading(Content source, {Strings? strings}) {
    final said = strings ?? StringsRegistry();
    return TaskOperation<FileEntry, TextFile>((op, entry) async {
      op.report(message: said.tr('Reading {name}…', args: {'name': entry.name}));

      final bytes = <int>[];
      await for (final chunk in source.read()) {
        // Между кусками, а не после: файл может быть большим, а сервер
        // медленным, и ждать конца чтения ради отмены незачем.
        op.checkCanceled();
        bytes.addAll(chunk);
      }
      op.checkCanceled();

      final file = decode(bytes);
      if (file == null) {
        throw FsError(entry.path, FsErrorKind.notSupported);
      }
      return file;
    });
  }
}
