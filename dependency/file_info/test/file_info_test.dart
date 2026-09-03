import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, который берётся и не справляется: так выглядит битый файл.
class _BrokenProvider implements NodeInfoProvider {
  @override
  String get id => 'broken';

  @override
  int get priority => 10;

  @override
  bool accepts(FileEntry entry, ContentType? type) => entry.name.endsWith('.broken');

  @override
  Future<List<NodeInfoSection>> describe(FileEntry entry, Content content) async =>
      throw const FsError('x', FsErrorKind.io);
}

/// Провайдер, которому сказать нечего.
class _SilentProvider implements NodeInfoProvider {
  @override
  String get id => 'silent';

  @override
  int get priority => 5;

  @override
  bool accepts(FileEntry entry, ContentType? type) => true;

  @override
  Future<List<NodeInfoSection>> describe(FileEntry entry, Content content) async => const [];
}

/// Модуль, объявляющий обоих: так это делает любой чужой модуль.
class _TestSources implements FcFrontendModule {
  const _TestSources();

  @override
  String get id => 'fc.test_sources';

  @override
  String get title => 'Test sources';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.nodeInfo((context) => _BrokenProvider());
    registry.nodeInfo((context) => _SilentProvider());
  }
}

void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз'), size: 3),
        FakeEntry.file('/home/data.bin', size: 1024),
        FakeEntry.file('/home/half.broken', size: 10),
      ])..home = '/home',
      modules: [...featureModules(), const _TestSources()],
    );
    await runtime.app.start();
  });

  /// Сведения о файле — тем же состоянием, каким их показывают окно и панель.
  ///
  /// Через состояние, а не через окно: рама к содержимому отношения не имеет,
  /// а лезть в потроха показанного окна — значит проверять разметку вместо
  /// сведений.
  Future<FileInfoScreen> infoOf(String name) async {
    final node = (await runtime.app.left.session.provider.resolvePath().run('/home/$name'))!;
    final screen = FileInfoScreen(
      app: runtime.app,
      entries: [entryValueOf(node)],
      contentOf: (entry) => NodeContent(node),
    );
    await pumpEventQueue();
    return screen;
  }

  group('окно', () {
    test('Cmd-I и Alt-Enter открывают сведения', () async {
      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-I'))?.id, FileInfoCommand.commandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Alt-Enter'))?.id, FileInfoCommand.commandId);
    });

    test('команда и правда показывает окно', () async {
      runtime.app.left.setCursorToName('notes.txt');
      await runtime.commands.create(FileInfoCommand.commandId)!.executeWith();

      expect(runtime.app.view.dialogs, hasLength(1));
      expect(runtime.app.view.dialogs.single.title, 'notes.txt');
    });

    test('о помеченном — одно окно со сводкой, а не десять подряд', () async {
      runtime.app.left.setMarks({
        for (final entry in runtime.app.left.entries)
          if (!entry.isParent) entry.name,
      });
      await runtime.commands.create(FileInfoCommand.commandId)!.executeWith();

      expect(runtime.app.view.dialogs, hasLength(1));
      expect(runtime.app.view.dialogs.single.title, contains('items'));
    });
  });

  group('провайдер основных полей', () {
    test('рассказывает имя, путь, тип и размер', () async {
      final screen = await infoOf('notes.txt');
      final rows = _rowsOf(screen, 'General');

      expect(rows['Name'], 'notes.txt');
      expect(rows['Path'], '/home/notes.txt');
      expect(rows['Type'], 'File');
      expect(rows['Size'], contains('3'));
      expect(rows['Extension'], 'txt');
    });

    test('у каталога размера нет: его не считают молча', () async {
      final screen = await infoOf('docs');

      expect(_rowsOf(screen, 'General')['Size'], isNull);
      expect(screen.canCount, isTrue);
    });

    test('кнопка считает — тем же обходом, что и Alt-Shift-Enter', () async {
      final screen = await infoOf('docs');

      await screen.count();

      expect(screen.directorySize, isNotNull);
    });
  });

  group('чужие провайдеры', () {
    test('взялся и не смог — ошибка в его разделе, это сведение о файле', () async {
      final screen = await infoOf('half.broken');

      final part = screen.parts.firstWhere((part) => part.id == 'broken');
      expect(part.error, isNotNull);
    });

    test('сказать нечего — раздела нет вовсе', () async {
      final screen = await infoOf('notes.txt');

      expect(screen.parts.map((part) => part.id), isNot(contains('silent')));
    });

    test('не взялся — тоже ничего: и раздела, и ошибки нет', () async {
      final screen = await infoOf('notes.txt');

      expect(screen.parts.map((part) => part.id), isNot(contains('broken')));
    });

    test('картинки добавляют своё, не трогая окна', () async {
      // Тот самый сторож: провайдер из чужого модуля встаёт в окно без единой
      // правки в шелле.
      expect(runtime.app.nodeInfoProviders.map((provider) => provider.id), containsAll(['basics', 'image']));
    });
  });

  group('последний просмотрщик', () {
    Future<ViewportState?> view(String name) async {
      runtime.app.left.setCursorToName(name);
      await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
      await pumpEventQueue();
      return runtime.app.view.contentAt(ViewportPosition.fullscreen);
    }

    test('F3 на непонятном файле показывает сведения, а не отказ', () async {
      expect(await view('data.bin'), isA<FileInfoScreen>());
    });

    test('а текст по-прежнему открывает текстовый', () async {
      expect(await view('notes.txt'), isA<TextViewerScreen>());
    });
  });
}

/// Строки раздела по его заголовку.
Map<String, String> _rowsOf(FileInfoScreen screen, String title) {
  for (final part in screen.parts) {
    for (final section in part.sections) {
      if (section.title == title) {
        return {for (final row in section.rows) row.label: row.value};
      }
    }
  }
  return const {};
}
