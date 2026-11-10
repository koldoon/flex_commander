import 'dart:io';

import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/modules/clipboard/system_file_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(SystemFileClipboard.channelName);
  late AppRuntime runtime;
  late Directory temp;
  late Directory source;
  late Directory target;
  late int change;
  late List<String> onBoard;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_file_clipboard_live');
    source = await Directory('${temp.path}/source').create();
    target = await Directory('${temp.path}/target').create();
    await File('${source.path}/notes.txt').writeAsString('notes');
    change = 10;
    onBoard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'write':
          onBoard = ((call.arguments as Map)['paths'] as List).cast<String>();
          return ++change;
        case 'read':
          return {'paths': onBoard, 'change': change};
      }
      return null;
    });
    runtime = await initIsolated(
      frontendModules(),
      overrides: AppOverrides(window: FakeWindowService()),
      settingsPath: '${temp.path}/settings.json',
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await runtime.dispose();
    await temp.delete(recursive: true);
  });

  test('Cmd-X и Cmd-V переносят настоящий файл через изолированное ядро', () async {
    final app = runtime.app;
    await app.start();
    expect(await app.left.openPath(source.path), isTrue);
    expect(await app.right.openPath(target.path), isTrue);
    await waitUntil(() => app.left.entries.any((entry) => entry.name == 'notes.txt') && !app.right.busy);
    app.left.setCursorToName('notes.txt');
    await waitUntil(() => app.left.currentEntry?.name == 'notes.txt');

    expect(await app.commands.runAndWait(ClipboardCutCommand.commandId), isTrue);
    app.activate(app.right);
    expect(await app.commands.runAndWait(ClipboardPasteCommand.copyId), isTrue);
    await waitUntil(() => app.view.dialogs.isNotEmpty);

    expect(app.view.dialogs.single.title, 'Move «notes.txt»');
    app.view.dialogs.single.onSubmit?.call();
    await waitUntilAsync(
      () async => await File('${target.path}/notes.txt').exists() && !await File('${source.path}/notes.txt').exists(),
    );

    expect(await File('${target.path}/notes.txt').readAsString(), 'notes');
    await waitUntil(() => app.view.dialogs.isEmpty && !app.left.busy && !app.right.busy);
  });
}
