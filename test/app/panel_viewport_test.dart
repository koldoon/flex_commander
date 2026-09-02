import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, содержимое которого рисуется не таблицей файлов.
class _SearchProvider extends InMemoryTreeProvider implements PanelContent {
  _SearchProvider(super.entries);

  @override
  String get contentKind => 'search';
}

/// Модуль, который приносит своё содержимое панели.
class _SearchModule implements FcFrontendModule {
  const _SearchModule();

  @override
  String get id => 'test.search';

  @override
  String get title => 'Search results';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.viewport('search', (context, panel) => const Center(child: Text('Результаты поиска')));
  }
}

void main() {
  testWidgets('панель рисует то, чем объявлен её вид содержимого', (tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final runtime = await testApp(
      provider: _SearchProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)]),
      modules: [...featureModules(), const _SearchModule()],
    );

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();

    expect(runtime.app.left.contentKind, 'search');
    expect(find.text('Результаты поиска'), findsNWidgets(2));
    // Таблицы файлов в панели нет вовсе: вид содержимого заменяет её целиком.
    expect(find.text('Name'), findsNothing);
  });

  testWidgets('незнакомый вид содержимого рисуется таблицей файлов', (tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Модуль, объявивший вид, отключён — панель всё равно обязана что-то
    // показать.
    final runtime = await testApp(
      provider: _SearchProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)]),
      modules: featureModules(),
    );

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsNWidgets(2));
  });

  test('обычный провайдер показывает файлы', () async {
    final runtime = await testApp(provider: InMemoryTreeProvider([FakeEntry.directory('/home')]));

    expect(runtime.app.left.contentKind, PanelViewports.files);
  });
}
