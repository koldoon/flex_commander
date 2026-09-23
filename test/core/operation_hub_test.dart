import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/operation_hub.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/remote_operation.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Работы через границу: заявка туда, ход дела и вопросы обратно.
void main() {
  late InMemoryTreeProvider provider;
  late ProviderRegistry registry;
  late CoreServer core;
  late Link link;
  late MeasuredSizes sizes;

  PanelSession sessionFor(String path) =>
      PanelSession(settings: PanelSettings.defaults(path), registry: registry, editor: const TreeTransferEngine());

  /// Работа, которая делает то, что ей велят доводы: рассказывает, спрашивает,
  /// падает или ждёт.
  Operation<OperationInputs, void> probe(FcServices services) =>
      TaskOperation<OperationInputs, void>((op, inputs) async {
        if (inputs.option<bool>('fails') ?? false) {
          throw const FsError('/nowhere', FsErrorKind.notFound);
        }
        op.report(message: 'Работаю над ${inputs.targets.length}', itemsTransferred: 1, itemsTotal: 2);
        if (inputs.option<bool>('asks') ?? false) {
          final answer = await op.ask(
            OperationRequest(
              message: 'Продолжать?',
              options: const [OperationRequestOption('yes', 'Yes'), OperationRequestOption('no', 'No')],
              enterOption: const OperationRequestOption('no', 'No'),
            ),
          );
          op.report(message: 'Ответили ${answer.id}');
        }
        if (inputs.option<bool>('waits') ?? false) {
          for (var step = 0; step < 100; step++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            op.checkCanceled();
          }
        }
      });

  /// Работа, которая отчитывается часто и подолгу: так ведёт себя поиск —
  /// отчёт на каждый каталог.
  Operation<OperationInputs, void> storm(FcServices services) =>
      TaskOperation<OperationInputs, void>((op, inputs) async {
        for (var step = 0; step < 40; step++) {
          op.report(message: 'шаг $step', itemsTransferred: step, itemsTotal: 40);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

  // Окно придерживания — настоящее: эта проверка как раз про него.
  setUp(() => OperationHub.reportWindow = OperationHub.defaultReportWindow);

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ])..home = '/home';
    registry = ProviderRegistry(root: provider);
    sizes = MeasuredSizes();
    // Сервер, как `ssh://`: цель работы на нём называется путём целиком, и
    // разбирать этот путь ядру приходится самому.
    registry.registerAddress(
      'tsh',
      () => TaskOperation<Uri, TreeProvider>(
        (op, address) async => InMemoryAddressProvider(
          address: address,
          entries: [
            FakeEntry.directory('/etc'),
            FakeEntry.file('/etc/daemon.json', content: [1, 2]),
          ],
        ),
      ),
    );

    core = CoreServer(
      left: sessionFor('/home'),
      right: sessionFor('/home'),
      registry: registry,
      operations: {
        'test.probe': OperationRegistration(probe),
        // Та же работа, но объявленная читающей: посчитанное после неё
        // остаётся (`docs/spec/directory-sizes.md`, §12.4).
        'test.reads': OperationRegistration(probe, writes: false),
        'test.storm': OperationRegistration(storm),
        ...const AppShellKinds().kinds,
      },
      sizes: sizes,
    );
    link = LoopbackLink(core);
  });

  tearDown(() async {
    await link.dispose();
    await core.dispose();
  });

  Future<void> openLeft() async {
    await link.call(const OpenPath(PanelId.left, '/home'));
  }

  /// Строка панели ссылкой — так её называет экран, заводя работу
  /// (`docs/spec/client-server.md`, §5.6).
  EntryRef row(String name) {
    final entry = core.session(PanelId.left).entries.firstWhere((entry) => entry.name == name);
    return EntryRef.inPanel(PanelId.left, entry.id, path: entry.path);
  }

  test('работа рождается в ядре и рассказывает о себе', () async {
    await openLeft();
    link.tell(const SetMarks(PanelId.left, {'/home/notes.txt', '/home/report.txt'}, 1));
    await pumpEventQueue();

    final operation = RemoteOperation(link);
    final seen = <String>[];
    operation.status.addListener(() => seen.add(operation.status.message));

    await operation.run(OperationSpec(kind: 'test.probe', targets: Targets.marked(PanelId.left, under: null)));

    expect(seen, contains('Работаю над 2'), reason: 'цели развернуло ядро — по имени набора');
    expect(operation.state, OperationState.complete);
  });

  test('цель, названная путём, разворачивается корнем дерева', () async {
    final operation = RemoteOperation(link);
    final seen = <String>[];
    operation.status.addListener(() => seen.add(operation.status.message));

    await operation.run(const OperationSpec(kind: 'test.probe', targets: Targets.paths(['/home/notes.txt'])));

    expect(seen, contains('Работаю над 1'));
  });

  test('цель на сервере — тоже путь, и он разбирается', () async {
    // Сохранение в редакторе называет цель путём: `ssh://…/etc/docker/daemon.json`.
    // Разбор отказывал на чужой схеме, и до источника дело не доходило вовсе
    // (`docs/spec/address-targets.md`).
    final operation = RemoteOperation(link);
    final seen = <String>[];
    operation.status.addListener(() => seen.add(operation.status.message));

    await operation.run(
      const OperationSpec(kind: 'test.probe', targets: Targets.paths(['tsh://tester@example.org/etc/daemon.json'])),
    );

    expect(seen, contains('Работаю над 1'));
    expect(operation.state, OperationState.complete);
  });

  group('посчитанные размеры', () {
    /// Узел каталога — для памяти: она различает каталоги по провайдеру, и
    /// одного пути ей мало.
    DirectoryNode home() => DirectoryNode(provider: provider, name: 'home', parent: provider.rootDirectory);

    DirectoryNode docs() => DirectoryNode(provider: provider, name: 'docs', parent: home());

    const totals = DirectoryTotals(bytes: 300, workBytes: 300, entries: 2);

    test('своя работа забывает посчитанное', () async {
      sizes.remember(docs(), totals);

      await RemoteOperation(link).run(const OperationSpec(kind: 'test.probe', targets: Targets.paths(['/home/docs'])));

      expect(sizes.take(docs()), isNull, reason: 'работа писала в этот каталог — число стало вчерашним');
    });

    test('работа в файле забывает каталог, в котором он лежит', () async {
      sizes.remember(home(), totals);

      await RemoteOperation(
        link,
      ).run(const OperationSpec(kind: 'test.probe', targets: Targets.paths(['/home/notes.txt'])));

      expect(sizes.take(home()), isNull, reason: 'изменился каталог, а не файл сам по себе');
    });

    test('читающая работа посчитанного не трогает', () async {
      sizes.remember(docs(), totals);

      await RemoteOperation(link).run(const OperationSpec(kind: 'test.reads', targets: Targets.paths(['/home/docs'])));

      expect(sizes.take(docs()), totals, reason: 'подсчёт стёр бы ровно то, ради чего шёл');
    });
  });

  test('вопрос доходит до этой стороны, ответ — обратно', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    final asked = <OperationRequest>[];
    operation.requests.listen(asked.add);
    final done = operation.run(
      OperationSpec(kind: 'test.probe', targets: Targets.row(row('notes.txt')), options: const {'asks': true}),
    );
    await pumpEventQueue();

    expect(asked, hasLength(1));
    expect(asked.single.message, 'Продолжать?');
    asked.single.respond(const OperationRequestOption('yes', 'Yes'));
    await done;

    expect(operation.status.message, 'Ответили yes', reason: 'ответ вернулся той работе, что спрашивала');
  });

  test('вопрос без слушателя решается сам собой', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    // Никто не подписан на `requests`: работу запустили без окна.
    await operation.run(
      OperationSpec(kind: 'test.probe', targets: Targets.row(row('notes.txt')), options: const {'asks': true}),
    );

    expect(operation.status.message, 'Ответили no', reason: 'берётся вариант по умолчанию');
  });

  test('отмена доходит до работы', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    final done = operation.run(
      OperationSpec(kind: 'test.probe', targets: Targets.row(row('notes.txt')), options: const {'waits': true}),
    );
    await pumpEventQueue();
    operation.cancel();

    await expectLater(done, throwsA(isA<OperationCanceled>()));
    expect(operation.state, OperationState.canceled);
  });

  test('отказ приезжает причиной, а не молчанием', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    await expectLater(
      operation.run(const OperationSpec(kind: 'test.probe', options: {'fails': true})),
      throwsA(isA<FsError>().having((error) => error.kind, 'вид', FsErrorKind.notFound)),
    );
    expect(operation.state, OperationState.error);
  });

  test('работы, которой нет, не бывает молча', () async {
    final operation = RemoteOperation(link);

    await expectLater(operation.run(const OperationSpec(kind: 'нет.такой')), throwsA(isA<Object>()));
  });

  test('копирование идёт настоящей работой ядра', () async {
    await openLeft();
    link.tell(const SetMarks(PanelId.left, {'/home/notes.txt'}, 1));
    await link.call(const OpenPath(PanelId.right, '/home/docs'));
    await pumpEventQueue();

    await RemoteOperation(link).run(
      OperationSpec(
        kind: FileOperations.copy,
        targets: Targets.marked(PanelId.left, under: null),
        destination: const Destination.inPanel(PanelId.right, path: '/home/docs'),
      ),
    );

    expect(provider.entryAt('/home/docs/notes.txt'), isNotNull);
  });

  test('отчёты о ходе работы не заваливают границу, а последний доходит', () async {
    // Отчёт — это «сейчас идёт вот это», а не запись в журнал: терять
    // промежуточные не жалко, важен последний
    // (`docs/spec/growing-listing.md`, §5).
    final sent = <ProgressReport>[];
    final watching = link.events.listen((event) {
      if (event is OperationProgress) {
        sent.add(event.report);
      }
    });
    addTearDown(watching.cancel);

    final operation = RemoteOperation(link);
    await operation.run(const OperationSpec(kind: 'test.storm', targets: Targets.paths(['/home/notes.txt'])));

    // Работа отчиталась сорок раз за четыре десятых секунды; через границу
    // уходит не чаще десяти раз в секунду.
    expect(sent.length, lessThan(15), reason: 'через границу ушло ${sent.length} отчётов из сорока');
    expect(sent, isNotEmpty, reason: 'ход работы не доехал вовсе');
    expect(sent.last.message, 'шаг 39', reason: 'последний отчёт потерялся в ограничителе');
  });
}

/// Работы оболочки приложения — те же, что в настоящей сборке.
class AppShellKinds {
  const AppShellKinds();

  Map<String, OperationRegistration> get kinds {
    final collected = <String, OperationRegistration>{};
    const AppShell().installBackend(_Collector(collected));
    return collected;
  }
}

/// Реестр, который запоминает только работы: остальное объявлению не мешает.
class _Collector implements BackendRegistry {
  const _Collector(this._operations);

  final Map<String, OperationRegistration> _operations;

  @override
  void operation(String kind, OperationFactory factory, {bool writes = true}) =>
      _operations[kind] = OperationRegistration(factory, writes: writes);

  @override
  FcServices get services => throw UnimplementedError();

  @override
  SettingsScope get settings => throw UnimplementedError();

  @override
  void column(ColumnSpec spec, {ColumnComparatorFactory? compare}) {}

  @override
  void addressProvider(String scheme, AddressFactory factory, {bool needsConnection = true}) {}

  @override
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}}) {}

  @override
  void rootProvider(TreeProvider Function(FcServices services) factory) {}

  @override
  void service<T extends Object>(T Function(FcServices services) factory) {}

  @override
  void strings(String language, Map<String, String> words) {}

  @override
  void plurals(String language, Map<String, PluralForms> forms) {}
}
