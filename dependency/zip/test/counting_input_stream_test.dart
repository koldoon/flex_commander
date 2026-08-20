import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Поток, который рассказывает, сколько из него прочитали.
void main() {
  late Directory temp;
  late String path;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_zip_counting');
    path = p.join(await temp.resolveSymbolicLinks(), 'data.bin');
    await File(path).writeAsBytes(Uint8List.fromList(List.generate(4096, (i) => i % 256)));
  });

  tearDown(() => temp.delete(recursive: true));

  test('сообщает о каждом прочитанном куске', () async {
    final reported = <int>[];
    final stream = CountingInputStream(InputFileStream(path), reported.add);

    while (!stream.isEOS) {
      stream.readBytes(1024);
    }
    await stream.close();

    expect(reported, [1024, 1024, 1024, 1024]);
  });

  test('второй проход считается как работа, а не как повтор', () async {
    // Упаковщик читает запись дважды: ради контрольной суммы и ради сжатия.
    // Второй проход — самая долгая часть, и молчать о нём значило бы замереть
    // на середине работы.
    var total = 0;
    final stream = CountingInputStream(InputFileStream(path), (bytes) => total += bytes);

    stream.readBytes(4096);
    stream.reset();
    stream.readBytes(4096);
    await stream.close();

    expect(total, 8192);
  });

  test('повторное чтение того же места счёт не двигает', () async {
    var total = 0;
    final stream = CountingInputStream(InputFileStream(path), (bytes) => total += bytes);

    stream.readBytes(1024);
    stream.rewind(1024);
    stream.readBytes(1024);
    await stream.close();

    // Перемотка — не работа: назад счёт не едет, а перечитанное не удваивается.
    expect(total, 2048);
  });

  test('длина и конец потока — как у настоящего', () async {
    final inner = InputFileStream(path);
    final stream = CountingInputStream(InputFileStream(path), (_) {});

    expect(stream.length, inner.length);
    expect(stream.isEOS, isFalse);

    stream.readBytes(4096);
    expect(stream.isEOS, isTrue);

    await inner.close();
    await stream.close();
  });

  test('упаковщик читает через него и сообщает о ходе', () async {
    final reported = <int>[];
    final archivePath = p.join(temp.path, 'out.zip');

    final output = OutputFileStream(archivePath);
    final encoder = ZipEncoder()..startEncode(output);
    final content = CountingInputStream(InputFileStream(path), reported.add);

    encoder.add(ArchiveFile.stream('data.bin', content));
    encoder.endEncode();
    await output.close();

    // Ход внутри записи виден, и объём работы — оба прохода по ней.
    expect(reported, isNotEmpty);
    expect(reported.fold<int>(0, (sum, value) => sum + value), 4096 * 2);
    expect(File(archivePath).existsSync(), isTrue);
  });
}
