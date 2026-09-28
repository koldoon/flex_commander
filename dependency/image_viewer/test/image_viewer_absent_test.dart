import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'images.dart';

/// Без просмотрщика изображений приложение собирается, а картинки и разметка
/// достаются текстовому.
///
/// Это и есть проверка правила «возможность приносит модуль»: выключили —
/// пропала одна возможность, а не сборка.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/icon.svg', content: svgSource.codeUnits),
        FakeEntry.file('/home/a.png', content: imageOf(pngData)),
      ])..home = '/home',
      // Все, кроме него самого.
      modules: [...featureModules().where((module) => module is! ImageViewer)],
    );
    await runtime.app.start();
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  ViewportState? shownFullscreen() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  test('`.svg` снова открывает текстовый', () async {
    await view('icon.svg');

    expect(shownFullscreen(), isA<TextViewerScreen>());
  });

  test('команд просмотрщика изображений нет вовсе', () async {
    expect(runtime.commands.find('image.source'), isNull);
    expect(runtime.commands.find('image.find'), isNull);
    expect(runtime.commands.find('image.fit'), isNull);
  });

  test('а приложение живо: остальное на месте', () async {
    expect(runtime.commands.find(ViewFileCommand.commandId), isNotNull);
    expect(runtime.app.left, isNotNull);
  });
}
