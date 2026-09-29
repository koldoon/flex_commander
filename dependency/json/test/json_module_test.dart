import 'package:fc_api/fc_api.dart';
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

  FileEntry file(String name) => FileEntry(name: name, kind: EntryKind.file, path: '/home/$name', size: 1);

  test('форматтер объявлен', () async {
    await withModules(featureModules(), (app) {
      expect(app.formatters.map((spec) => spec.id), contains('json'));
    });
  });

  test('берётся только за свой файл', () async {
    await withModules(featureModules(), (app) {
      final spec = app.formatters.firstWhere((spec) => spec.id == 'json');

      expect(spec.accepts(file('package.json'), null), isTrue);
      expect(spec.accepts(file('PACKAGE.JSON'), null), isTrue, reason: 'регистр имени не важен');
      expect(spec.accepts(file('main.dart'), null), isFalse);
      // Не `.json`, хотя и похоже: в `jsonc` бывают комментарии, и разбор на
      // них сломается.
      expect(spec.accepts(file('tsconfig.jsonc'), null), isFalse);
      expect(spec.accepts(file('json'), null), isFalse, reason: 'имя без расширения');
    });
  });

  test('без модуля форматтеров нет вовсе', () async {
    // Доказательство, что умение приносит модуль: `.json` откроется текстом,
    // как раньше.
    await withModules(featureModules().where((module) => module.id != 'fc.json').toList(), (app) {
      expect(app.formatters, isEmpty);
    });
  });
}
