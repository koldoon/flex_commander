
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/remote_operation.dart';
import 'package:flex_commander/modules/app_shell_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// Работы через границу: заявка туда, ход дела и вопросы обратно.
void main() {
  late InMemoryTreeProvider provider;
  late ProviderRegistry registry;
  late CoreServer core;
  late Link link;

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

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ])..home = '/home';
    registry = ProviderRegistry(root: provider);

    core = CoreServer(
      left: sessionFor('/home'),
      right: sessionFor('/home'),
      registry: registry,
      operations: {'test.probe': probe, ...const AppShellBackendKinds().kinds},
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

  test('работа рождается в ядре и рассказывает о себе', () async {
    await openLeft();
    link.tell(const SetMarks(PanelId.left, {'notes.txt', 'report.txt'}));
    await pumpEventQueue();

    final operation = RemoteOperation(link);
    final seen = <String>[];
    operation.status.addListener(() => seen.add(operation.status.message));

    await operation.run(const OperationSpec(kind: 'test.probe', targets: Targets.marked(PanelId.left)));

    expect(seen, contains('Работаю над 2'), reason: 'цели развернуло ядро — по имени набора');
    expect(operation.state, OperationState.complete);
  });

  test('вопрос доходит до этой стороны, ответ — обратно', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    final asked = <OperationRequest>[];
    operation.requests.listen(asked.add);
    final done = operation.run(
      const OperationSpec(kind: 'test.probe', targets: Targets.current(PanelId.left), options: {'asks': true}),
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
      const OperationSpec(kind: 'test.probe', targets: Targets.current(PanelId.left), options: {'asks': true}),
    );

    expect(operation.status.message, 'Ответили no', reason: 'берётся вариант по умолчанию');
  });

  test('отмена доходит до работы', () async {
    await openLeft();
    final operation = RemoteOperation(link);

    final done = operation.run(
      const OperationSpec(kind: 'test.probe', targets: Targets.current(PanelId.left), options: {'waits': true}),
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
    link.tell(const SetMarks(PanelId.left, {'notes.txt'}));
    await link.call(const OpenPath(PanelId.right, '/home/docs'));
    await pumpEventQueue();

    await RemoteOperation(link).run(
      const OperationSpec(kind: FileOperations.copy, targets: Targets.marked(PanelId.left), destination: PanelId.right),
    );

    expect(provider.entryAt('/home/docs/notes.txt'), isNotNull);
  });
}

/// Работы оболочки приложения — те же, что в настоящей сборке.
class AppShellBackendKinds {
  const AppShellBackendKinds();

  Map<String, OperationFactory> get kinds {
    final collected = <String, OperationFactory>{};
    const AppShellBackend().installBackend(_Collector(collected));
    return collected;
  }
}

/// Реестр, который запоминает только работы: остальное объявлению не мешает.
class _Collector implements BackendRegistry {
  const _Collector(this._operations);

  final Map<String, OperationFactory> _operations;

  @override
  void operation(String kind, OperationFactory factory) => _operations[kind] = factory;

  @override
  FcServices get services => throw UnimplementedError();

  @override
  SettingsScope get settings => throw UnimplementedError();

  @override
  void addressProvider(String scheme, AddressFactory factory) {}

  @override
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}}) {}

  @override
  void rootProvider(TreeProvider Function(FcServices services) factory) {}

  @override
  void service<T extends Object>(T Function(FcServices services) factory) {}
}
