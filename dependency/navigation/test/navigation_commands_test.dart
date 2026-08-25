import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Открытие объекта системой — платформенная служба, и в тестах она подставная.
class _SystemOpenerModule implements FcModule {
  _SystemOpenerModule();

  final List<String> opened = [];

  @override
  String get id => 'test.opener';

  @override
  String get title => 'Fake opener';

  @override
  void install(FcRegistry registry) => registry.service<SystemOpener>((services) => (path) async => opened.add(path));
}

/// Переходы по дереву: команды, которым не нужен ни диалог, ни клавиатура.
void main() {
  late InMemoryTreeProvider provider;
  late Application app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.directory('/usr'),
    ]);
    // Приложение собирается по-настоящему — с этим модулем и без остальных:
    // так видно, что модуль самодостаточен.
    final runtime = await testApp(
      provider: provider,
      modules: [const Navigation(), _SystemOpenerModule()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    app = runtime.app;
    await app.start();
  });

  CommandService commands() => app.commands;

  Future<void> run(String id) => commands().create(id)!.executeWith();

  group('переход в корень', () {
    test('панель открывает корневой каталог провайдера', () async {
      expect(app.left.directory?.name, 'home');

      await run('panel.root');

      expect(app.left.directory, provider.rootDirectory);
      expect(app.left.nodes.map((node) => node.name), containsAll(['home', 'usr']));
    });

    test('пометка снимается: она относилась к прежнему каталогу', () async {
      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      expect(app.left.selection.isEmpty, isFalse);

      await run('panel.root');

      expect(app.left.selection.isEmpty, isTrue);
    });

    test('курсор встаёт в начало списка', () async {
      app.left.setCursorToName('report.xlsx');

      await run('panel.root');

      expect(app.left.cursorIndex, 0);
    });

    test('работает в активной панели', () async {
      app.toggleActivePanel();

      await run('panel.root');

      expect(app.right.directory, provider.rootDirectory);
      expect(app.left.directory?.name, 'home');
    });

    test('в самом корне команда недоступна', () async {
      await run('panel.root');

      // Идти больше некуда — кнопка и клавиша ничего не делают.
      expect(commands().isExecutable(commands().find('panel.root')!), isFalse);
    });

    test('команда видна в списке команд и закреплена за клавишей', () {
      expect(commands().find('panel.root')?.label, 'Root');
      // Вне macOS «командная» клавиша — Ctrl, поэтому сравнение идёт с тем же
      // разбором, каким привязка и создавалась.
      expect(
        commands().bindingsOf('panel.root').map((binding) => binding.keys),
        contains(KeyCombination.parse('Cmd-/')),
      );
    });
  });
}
