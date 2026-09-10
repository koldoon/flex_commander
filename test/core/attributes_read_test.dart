import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/session_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

/// Атрибуты объекта через границу: одна просьба — один ответ.
///
/// Проверяется здесь ровно то, чего не видно ни в провайдере, ни в окне:
/// **целое складывает ядро**. Обычные атрибуты, имена владельца и расширенные
/// атрибуты — три разных умения, каждое бывает порознь, и собрать их в одно
/// значение может только тот, кто держит источник (`spec/file-attributes.md`,
/// §3.4).
class _KnowingProvider extends InMemoryTreeProvider implements NodeAttributesEditor, NodeXattrEditor, UserDirectory {
  _KnowingProvider(super.entries);

  /// Что назначили — тест смотрит сюда.
  final List<String> done = [];

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async => NodeAttributes(
    mode: 0x81A4,
    modeString: '-rw-r--r--',
    uid: 501,
    gid: 20,
    modified: DateTime.utc(2020, 1, 2, 3, 4, 5),
    accessed: DateTime.utc(2020, 1, 2, 3, 4, 6),
    canEditMode: true,
    canEditTimes: true,
    canEditOwner: true,
  );

  @override
  Future<void> setMode(FsNode node, int mode) async => done.add('mode ${mode.toRadixString(8)}');

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async => done.add('times');

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async => done.add('owner $uid:$gid');

  @override
  Future<List<Xattr>> readXattrs(FsNode node) async => [Xattr('com.apple.quarantine', '0083;Safari'.codeUnits)];

  @override
  Future<void> setXattr(FsNode node, String name, List<int> value) async => done.add('xattr $name');

  @override
  Future<void> removeXattr(FsNode node, String name) async => done.add('unxattr $name');

  @override
  Future<String> userName(int uid) async => uid == 501 ? 'koldoon' : '';

  @override
  Future<String> groupName(int gid) async => gid == 20 ? 'staff' : '';

  @override
  Future<int?> userId(String name) async => name == 'koldoon' ? 501 : null;

  @override
  Future<int?> groupId(String name) async => name == 'staff' ? 20 : null;
}

/// Тот же провайдер, но об атрибутах не знающий ничего: архив.
class _SilentProvider extends InMemoryTreeProvider {
  _SilentProvider(super.entries);
}

/// Умеет обычные атрибуты и только их — как сервер по SFTP: ни расширенных,
/// ни имён пользователей.
class _PlainProvider extends InMemoryTreeProvider implements NodeAttributesEditor {
  _PlainProvider(super.entries);

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async =>
      const NodeAttributes(mode: 0x81A4, modeString: '-rw-r--r--', uid: 1000, gid: 1000, canEditMode: true);

  @override
  Future<void> setMode(FsNode node, int mode) async {}

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async {}

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async {}
}

/// Умеет, но не смог: битый объект или отказ по правам.
class _FailingProvider extends InMemoryTreeProvider implements NodeAttributesEditor {
  _FailingProvider(super.entries);

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async =>
      throw FsError(node.pathString, FsErrorKind.permissionDenied);

  @override
  Future<void> setMode(FsNode node, int mode) async {}

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async {}

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async {}
}

void main() {
  late CoreServer core;
  late Link link;
  late SessionMirror panel;

  Future<void> start(InMemoryTreeProvider provider) async {
    PanelSession sessionFor(String path) => PanelSession(
      settings: PanelSettings.defaults(path),
      registry: ProviderRegistry(root: provider),
      editor: const TreeTransferEngine(),
    );

    core = CoreServer(
      left: sessionFor('/home'),
      right: sessionFor('/home'),
      registry: ProviderRegistry(root: provider),
    );
    link = LoopbackLink(core);
    final ready = await link.call(const Handshake()) as CoreReady;
    panel = SessionMirror(
      id: PanelId.left,
      link: link,
      state: ready.states[PanelId.left]!,
      listing: ready.listings[PanelId.left]!,
    );
    await panel.openPath('/home');
  }

  List<FakeEntry> entries() => [FakeEntry.directory('/home'), FakeEntry.file('/home/report.txt', size: 20)];

  FileEntry fileRow() => panel.entries.firstWhere((entry) => entry.name == 'report.txt');

  tearDown(() async {
    await link.dispose();
    await core.dispose();
  });

  test('целое собирается из трёх умений сразу', () async {
    await start(_KnowingProvider(entries()));

    final attributes = await panel.readAttributes(fileRow());

    expect(attributes.modeString, '-rw-r--r--');
    expect(attributes.permissions, 0x1A4);
    // Имена пришли не от того, кто читал режим: их знает словарь машины.
    expect(attributes.owner, 'koldoon');
    expect(attributes.group, 'staff');
    // А расширенные атрибуты — от третьего умения, и только вместе с ними
    // появляется право их править.
    expect(attributes.xattrs.single.name, 'com.apple.quarantine');
    expect(attributes.canEditXattrs, isTrue);
    expect(attributes.canEditMode, isTrue);
  });

  test('источник без умений отвечает пустотой, а не отказом', () async {
    await start(_SilentProvider(entries()));

    final attributes = await panel.readAttributes(fileRow());

    expect(attributes, same(NodeAttributes.unknown));
    expect(attributes.canEditMode, isFalse);
    expect(attributes.canEditXattrs, isFalse);
  });

  test('умеющий только обычные атрибуты не обещает ни имён, ни расширенных', () async {
    await start(_PlainProvider(entries()));

    final attributes = await panel.readAttributes(fileRow());

    expect(attributes.canEditMode, isTrue);
    // Право на правку расширенных приходит вместе с самим списком, а не флагом
    // «наверное, есть», — поэтому здесь его нет.
    expect(attributes.canEditXattrs, isFalse);
    expect(attributes.xattrs, isEmpty);
    // Словаря у источника нет, и владелец остаётся числом: врать про имя хуже,
    // чем показать число.
    expect(attributes.owner, isEmpty);
    expect(attributes.uid, 1000);
  });

  test('взявшийся и не смогший отвечает отказом, а не пустотой', () async {
    await start(_FailingProvider(entries()));

    // Разница не косметическая: «править нечем» и «не пустили» — разные
    // ответы, и окно скажет о них разное.
    await expectLater(
      panel.readAttributes(fileRow()),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
    );
  });

  test('у «..» атрибутов нет: спрашивать не о чем', () async {
    await start(_KnowingProvider(entries()));

    final parent = panel.entries.firstWhere((entry) => entry.isParent);

    expect(await panel.readAttributes(parent), same(NodeAttributes.unknown));
  });

  test('значение читается заново, а не берётся из строки списка', () async {
    await start(_KnowingProvider(entries()));

    final row = fileRow();
    final attributes = await panel.readAttributes(row);

    // В списке у подставного дерева режим свой — `rwxrwxrwx`; ответ пришёл не
    // оттуда, и это единственное, что отличает свежее от устаревшего.
    expect(row.attributes.modeString, isNot(attributes.modeString));
  });
}
