import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Сборка архива в отдельном изоляте.
///
/// Сжатие в `archive` синхронное: пока оно идёт, главный изолят не отдаёт
/// управление вовсе. Отсюда и всё, что проверяется здесь: работа уехала, а
/// отмена и счёт остались рабочими.
void main() {
  late Directory temp;
  late String root;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_zip_encoding');
    root = await temp.resolveSymbolicLinks();
    await File(p.join(root, 'notes.txt')).writeAsString('заметки');
    await File(p.join(root, 'readme.md')).writeAsString('руководство');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  List<ZipItem> entries() => [
    const ZipItem.directory('docs'),
    ZipItem.file('docs/notes.txt', p.join(root, 'notes.txt')),
    ZipItem.file('docs/readme.md', p.join(root, 'readme.md')),
  ];

  Future<void> pack({
    required String archivePath,
    void Function(String name)? onEntryDone,
    void Function(int bytes)? onBytes,
  }) {
    final operation = TaskOperation<void>(
      (op) => encodeZipArchive(
        archivePath: archivePath,
        entries: entries(),
        level: 6,
        op: op,
        onEntryDone: onEntryDone,
        onBytes: onBytes,
      ),
    );
    return operation.result;
  }

  test('архив собирается со всем, что дали', () async {
    final archivePath = p.join(root, 'archive.zip');

    await pack(archivePath: archivePath);

    final archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
    expect(archive.files.map((file) => file.name), containsAll(['docs/', 'docs/notes.txt', 'docs/readme.md']));
  });

  test('о каждой записи сообщается по её готовности', () async {
    // Отмечает сделанное упаковщик, а не обход: иначе счётчик показывал бы
    // «2000 из 2000», пока файлы ещё бегут.
    final done = <String>[];
    var bytes = 0;

    await pack(archivePath: p.join(root, 'archive.zip'), onEntryDone: done.add, onBytes: (n) => bytes += n);

    expect(done, ['docs', 'docs/notes.txt', 'docs/readme.md']);
    expect(bytes, greaterThan(0));
  });

  test('просьба прервать не тонет в ожидании изолята', () async {
    // Кнопка «Cancel» только **просит** прервать: вопрос «Abort the
    // operation?» и сама отмена происходят в `op.checkpoint()`. Пока тело
    // операции ждёт изолят, звать его больше некому — с `checkCanceled` вместо
    // `checkpoint` кнопка не делала ничего.
    final archivePath = p.join(root, 'archive.zip');

    final operation = TaskOperation<void>((op) async {
      op.requestCancel();
      await encodeZipArchive(archivePath: archivePath, entries: entries(), level: 6, op: op);
    });

    final questions = <String>[];
    operation.requests.listen((request) {
      questions.add(request.message);
      request.respond(OperationOption.abort);
    });

    await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
    expect(questions.single, 'Abort the operation?');
  });

  test('продолжить — значит продолжить', () async {
    final archivePath = p.join(root, 'archive.zip');

    final operation = TaskOperation<void>((op) async {
      op.requestCancel();
      await encodeZipArchive(archivePath: archivePath, entries: entries(), level: 6, op: op);
    });
    operation.requests.listen((request) => request.respond(OperationOption.resume));

    await operation.result;

    expect(await File(archivePath).exists(), isTrue);
  });
}
