import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_terminal/frontend.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Раздел настроек принадлежит тому модулю, который его просит.
///
/// Проверяется потому, что однажды не принадлежал: модуль просил область
/// **лениво**, из замыкания, а имя раздела в этот момент доставалось последнему
/// установленному модулю. Настройки терминала уехали в раздел редактора, и
/// заметно это стало только по чужим ключам в файле настроек.
void main() {
  test('настройки модуля лежат в его собственном разделе', () async {
    final store = InMemorySettingsStore(homePath: '/home');
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
      store: store,
    );
    await runtime.app.start();

    final line = runtime.app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;
    line.settings.typingGoesToLine = true;
    line.settings.history.add('ls');
    runtime.app.settings.modules.scope('fc.terminal').save();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final saved = <String, dynamic>{};
    runtime.app.settings.toMap(saved);
    final modules = saved['modules'] as Map<String, dynamic>;

    expect(modules['fc.terminal'], containsPair('typingGoesToLine', true));
    expect(modules['fc.terminal'], containsPair('history', ['ls']));
    // И ничего своего в чужом разделе: редактор объявлен последним, и прежде
    // всё уезжало к нему.
    expect(modules['fc.editor'], isNot(contains('typingGoesToLine')));
  });
}
