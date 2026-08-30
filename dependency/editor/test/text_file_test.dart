import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Чтение файла на правку: строго, потому что записывать обратно.
void main() {
  Future<FsNode> nodeWith(List<int> content) async {
    final disk = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/f', content: content)]);
    return (await disk.resolvePath().run('/home/f'))!;
  }

  Future<TextFile> read(List<int> content) async {
    final node = await nodeWith(content);
    return TextFile.reading(node.provider as FileContentProvider).run(node);
  }

  group('переводы строк помнятся', () {
    test('unix', () async {
      final file = await read(utf8.encode('раз\nдва'));

      expect(file.lineBreak, LineBreak.lf);
      expect(file.text, 'раз\nдва');
      expect(file.bytes, 'раз\nдва');
    });

    test('windows: разобрали в unix, вернули как было', () async {
      final file = await read(utf8.encode('раз\r\nдва\r\n'));

      expect(file.lineBreak, LineBreak.crlf);
      // Внутри работаем с одним видом — так проще всему остальному.
      expect(file.text, 'раз\nдва\n');
      // А наружу отдаём тот, каким файл был написан.
      expect(file.bytes, 'раз\r\nдва\r\n');
    });

    test('старый mac', () async {
      final file = await read(utf8.encode('раз\rдва'));

      expect(file.lineBreak, LineBreak.cr);
      expect(file.bytes, 'раз\rдва');
    });

    test('без переводов вовсе — unix', () async {
      expect((await read(utf8.encode('одна строка'))).lineBreak, LineBreak.lf);
    });
  });

  group('не текст на правку не берётся', () {
    test('битые байты — отказ, а не знаки замены', () async {
      // Просмотрщик такое покажет со знаками замены, и это честно: он
      // показывает. Записать их обратно значило бы испортить файл молча.
      await expectLater(
        () => read([0xC3, 0x28, 0x41, 0xFF]),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
      );
    });

    test('пустой файл — обычный текстовый', () async {
      final file = await read(const []);

      expect(file.text, isEmpty);
      expect(file.lineBreak, LineBreak.lf);
    });
  });
}
