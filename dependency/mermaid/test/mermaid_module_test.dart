import 'package:fc_api/fc_api.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль в собранном приложении: объявляет одну вещь и ничего больше.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> withModules(List<FcModule> modules, void Function(Application app) check) async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: modules,
    );
    await runtime.app.start();
    check(runtime.app);
  }

  test('рисовальщик врезок объявлен', () async {
    await withModules(featureModules(), (app) {
      expect(app.markdownBlocks.map((spec) => spec.id), contains('mermaid'));
    });
  });

  test('берётся только за свой язык', () async {
    await withModules(featureModules(), (app) {
      final spec = app.markdownBlocks.firstWhere((spec) => spec.id == 'mermaid');

      expect(spec.accepts('mermaid'), isTrue);
      expect(spec.accepts('dart'), isFalse);
      expect(spec.accepts('plantuml'), isFalse);
    });
  });

  test('без модуля реестр пуст — и врезка снова станет кодом', () async {
    await withModules([...featureModules().where((module) => module is! Mermaid)], (app) {
      expect(app.markdownBlocks, isEmpty);
    });
  });

  test('ни команд, ни клавиш модуль не приносит', () async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();

    // Всё, что он объявляет, — одна врезка. Ничего с именем `mermaid.*` быть
    // не должно.
    expect(runtime.commands.find('mermaid.draw'), isNull);
  });
}
