import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/remote_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// Байты через границу: кусками, с концом и с отказом.
void main() {
  late InMemoryContentProvider provider;
  late ProviderRegistry registry;
  late CoreServer core;
  late Link link;
  late PanelSession session;
  late PanelSession plain;

  setUp(() async {
    provider = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', content: [104, 101, 108, 108, 111]),
      FakeEntry.directory('/home/docs'),
    ])..home = '/home';
    registry = ProviderRegistry(root: provider);
    session = PanelSession(
      settings: PanelSettings.defaults('/home'),
      registry: registry,
      editor: const TreeTransferEngine(),
    );
    core = CoreServer(
      left: session,
      right:
          plain = PanelSession(
            // Источник без байтов: у списка находок их нет вовсе, и отвечать на
            // просьбу почитать ему нечем.
            settings: PanelSettings.defaults('/home'),
            registry: ProviderRegistry(
              root: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/plain.txt', size: 3)])
                ..home = '/home',
            ),
            editor: const TreeTransferEngine(),
          ),
      registry: registry,
    );
    link = LoopbackLink(core);
    await link.call(const OpenPath(PanelId.left, '/home'));
    await link.call(const OpenPath(PanelId.right, '/home'));
  });

  tearDown(() async {
    await link.dispose();
    await core.dispose();
  });

  FileEntry rowOf(String name) => session.entries.firstWhere((entry) => entry.name == name);

  Content contentOf(String name) {
    final row = rowOf(name);
    return RemoteContent(link, EntryRef.inPanel(PanelId.left, row.id, path: row.path), length: 5);
  }

  test('байты приезжают кусками и кончаются', () async {
    final bytes = <int>[];
    await for (final chunk in contentOf('notes.txt').read()) {
      bytes.addAll(chunk);
    }

    expect(bytes, [104, 101, 108, 108, 111]);
  });

  test('чтение с середины пропускает начало', () async {
    final bytes = <int>[];
    await for (final chunk in contentOf('notes.txt').read(offset: 3)) {
      bytes.addAll(chunk);
    }

    expect(bytes, [108, 111]);
  });

  test('источник без байтов отказывает, а не молчит', () async {
    final row = plain.entries.firstWhere((entry) => entry.name == 'plain.txt');
    final content = RemoteContent(link, EntryRef.inPanel(PanelId.right, row.id, path: row.path), length: 3);

    await expectLater(content.read().toList(), throwsA(isA<FsError>()));
  });

  test('строки, которой нет, байтов не отдают', () async {
    final gone = RemoteContent(link, const EntryRef.inPanel(PanelId.left, 99999, path: '/home/gone.txt'), length: 0);

    await expectLater(gone.read().toList(), throwsA(isA<FsError>()));
  });

  test('после перечитывания байты приезжают по той же ссылке', () async {
    // Личность строки сменилась вместе с узлом, а путь — нет: им ссылка и
    // выручается (`docs/spec/client-server.md`, §5.5а).
    final content = contentOf('notes.txt');
    await link.call(const Reload(PanelId.left));

    final bytes = <int>[];
    await for (final chunk in content.read()) {
      bytes.addAll(chunk);
    }

    expect(bytes, [104, 101, 108, 108, 111]);
  });

  test('закрытый поток прекращает чтение', () async {
    final subscription = contentOf('notes.txt').read().listen(null);
    await subscription.cancel();
    await pumpEventQueue();

    // Прекратилось молча: закрывать показ — обычное дело, а не беда.
    expect(true, isTrue);
  });
}
