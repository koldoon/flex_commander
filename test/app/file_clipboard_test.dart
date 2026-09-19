import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/clipboard/system_file_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Буфер обмена системы: что уходит наружу и что приезжает обратно
/// (`docs/spec/file-clipboard.md`, §§5–6).
///
/// Канал подставной: настоящий отвечает только из раннера, а проверять надо
/// правила, а не `AppKit`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late int change;
  late List<String> onBoard;

  /// Раннер-подставка: помнит последнюю запись и её номер.
  SystemFileClipboard clipboard() {
    const channel = MethodChannel(SystemFileClipboard.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'write':
          onBoard = ((call.arguments as Map)['paths'] as List).cast<String>();
          return ++change;
        case 'read':
          return {'paths': onBoard, 'change': change};
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    return SystemFileClipboard(channel: channel);
  }

  setUp(() {
    calls = [];
    change = 10;
    onBoard = [];
  });

  FileEntry local(String path) =>
      FileEntry(name: path.split('/').last, kind: EntryKind.file, path: path, realPath: path);

  /// Объект без настоящего пути: внутри архива или на сервере.
  FileEntry remote(String address, String name) => FileEntry(name: name, kind: EntryKind.file, path: address);

  test('местные объекты уходят настоящими путями', () async {
    final buffer = clipboard();

    await buffer.writeFiles([local('/home/notes.txt')], move: false);

    expect((calls.single.arguments as Map)['paths'], ['/home/notes.txt']);
    expect((calls.single.arguments as Map)['text'], isNull, reason: 'текст тут ни к чему — путь настоящий');
  });

  test('у кого настоящего пути нет, тот уходит текстом', () async {
    final buffer = clipboard();

    await buffer.writeFiles([remote('ssh://shark/etc/passwd', 'passwd')], move: false);

    final arguments = calls.single.arguments as Map;
    expect(arguments['paths'], isEmpty, reason: 'в Finder такое не вставить');
    expect(arguments['text'], 'ssh://shark/etc/passwd', reason: 'а в терминал и в письмо — вполне');
  });

  test('свой буфер возвращает адреса приложения и намерение', () async {
    final buffer = clipboard();
    await buffer.writeFiles([remote('ssh://shark/etc/passwd', 'passwd')], move: true);

    final files = await buffer.readFiles();

    expect(files!.addresses, ['ssh://shark/etc/passwd'], reason: 'система таких адресов не знает — знаем мы');
    expect(files.move, isTrue);
    expect(files.ours, isTrue);
  });

  test('чужая запись гасит намерение и отдаёт системные пути', () async {
    final buffer = clipboard();
    await buffer.writeFiles([local('/home/notes.txt')], move: true);

    // В буфер написал кто-то другой: номер записи стал другим.
    change++;
    onBoard = ['/home/report.md'];

    final files = await buffer.readFiles();

    expect(files!.addresses, ['/home/report.md']);
    expect(files.move, isFalse, reason: 'чужой буфер не даёт права переносить');
    expect(files.ours, isFalse);
  });

  test('в буфере не файлы — значит, файлов там нет', () async {
    final buffer = clipboard();
    change++;
    onBoard = [];

    expect(await buffer.readFiles(), isNull);
  });
}
