import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Настройки модуля-пробы.
class _ProbeSettings implements Serializable {
  _ProbeSettings({this.greeting = 'здравствуйте'});

  String greeting;

  @override
  void fromMap(Map<String, dynamic> m) => greeting = extract(greeting, m['greeting']);

  @override
  void toMap(Map<String, dynamic> m) => m['greeting'] = greeting;
}

/// Модуль, который читает своё при запуске и сохраняет по просьбе.
class _ProbeModule implements FcModule {
  _ProbeModule();

  late final SettingsScope scope;
  String? seenAtStartup;

  @override
  String get id => 'test.probe';

  @override
  String get title => 'Probe';

  @override
  void install(FcRegistry registry) {
    // Раздел получен во время объявления, а прочитан будет позже — к запуску
    // стартовой команды настройки уже с диска.
    scope = registry.settings;
    registry.startup((context) => _ReadSettingsCommand(this));
  }
}

class _ReadSettingsCommand extends AppCommand {
  _ReadSettingsCommand(this.module);

  final _ProbeModule module;

  @override
  String get id => 'test.probe.read';

  @override
  String get label => 'Read settings';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    module.seenAtStartup = module.scope.section(_ProbeSettings.new).greeting;
  }
}

void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home')]);
  });

  test('стартовая команда читает раздел своего модуля', () async {
    final settings = AppSettings.defaults('/home');
    settings.modules.fromMap({
      'test.probe': {'greeting': 'привет'},
    });
    final module = _ProbeModule();

    await testApp(provider: provider, modules: [module], settings: settings);

    expect(module.seenAtStartup, 'привет');
  });

  test('без сохранённого раздела берутся умолчания модуля', () async {
    final module = _ProbeModule();

    await testApp(provider: provider, modules: [module]);

    expect(module.seenAtStartup, 'здравствуйте');
  });

  test('раздел доступен и через приложение', () async {
    final module = _ProbeModule();
    final runtime = await testApp(provider: provider, modules: [module]);

    runtime.app.moduleSettings('test.probe').section(_ProbeSettings.new).greeting = 'добрый день';

    expect(module.scope.section(_ProbeSettings.new).greeting, 'добрый день');
  });

  test('просьба сохранить доходит до хранилища', () async {
    final store = InMemorySettingsStore();
    final module = _ProbeModule();
    await testApp(provider: provider, modules: [module], store: store);

    module.scope.section(_ProbeSettings.new).greeting = 'до свидания';
    module.scope.save();

    // Запись отложенная — как и у всего остального в настройках.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(serialize(store.saved!.modules), containsPair('test.probe', {'greeting': 'до свидания'}));
  });
}
