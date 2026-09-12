import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// История переходов — через границу и по наборам
/// (`docs/spec/session-history.md`, §6-7).
///
/// Настоящая сборка и настоящий файл: панель на этой стороне — зеркало, и
/// проверять надо, что шаги доезжают до него, а не остаются в ядре.
void main() {
  late Directory temp;
  late SettingsStore store;
  late InMemoryTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_history');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/pics'),
      FakeEntry.directory('/work'),
      FakeEntry.file('/home/notes.txt', size: 1),
    ])..home = '/home';
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AppRuntime> launch() async {
    final runtime = await initModules(
      backendModules(),
      frontendModules(),
      overrides: AppOverrides(provider: provider, store: store, window: FakeWindowService()),
    );
    await runtime.app.start();
    return runtime;
  }

  test('шаги доезжают до этой стороны — флагами и списком', () async {
    final runtime = await launch();
    final panel = runtime.app.left;

    expect(panel.canGoBack, isFalse, reason: 'ходить ещё некуда');
    await panel.openPath('/home/docs');
    await panel.openPath('/home/pics');

    expect(panel.canGoBack, isTrue);
    expect(panel.canGoForward, isFalse);

    final walked = await panel.history();
    expect([for (final step in walked.steps) step.path], ['/home', '/home/docs', '/home/pics']);
    expect(walked.index, 2, reason: 'стоим на последнем');

    await panel.goBack();
    expect(panel.currentPath, '/home/docs');
    expect(panel.canGoForward, isTrue);

    await runtime.dispose();
  });

  test('история переживает перезапуск вместе с сессией', () async {
    final first = await launch();
    await first.app.left.openPath('/home/docs');
    await first.app.left.openPath('/home/pics');
    await first.app.left.goBack();
    await first.dispose();

    final saved = await store.load();
    expect([for (final step in saved.left.history) step.path], ['/home', '/home/docs', '/home/pics']);
    expect(saved.left.historyIndex, 1, reason: 'закрыли, вернувшись на шаг назад');

    final second = await launch();
    final panel = second.app.left;
    expect(panel.currentPath, '/home/docs', reason: 'сессия открылась там, где её закрыли');
    expect(panel.canGoForward, isTrue, reason: '«вперёд» ведёт туда же, куда вело до перезапуска');

    await panel.goForward();
    expect(panel.currentPath, '/home/pics');

    await second.dispose();
  });

  test('набор приносит свою историю туда, где его показали', () async {
    final runtime = await launch();
    final app = runtime.app;

    // Первый набор прошёл `/home` → `/home/docs`; второй заводится рядом и
    // начинает свою дорогу с того места, где его открыли.
    final first = app.left;
    await first.openPath('/home/docs');
    final second = (await app.openPanel(ViewportPosition.left)).session;
    await second.openPath('/work');

    final theirs = [for (final step in (await second.history()).steps) step.path];
    expect(theirs, ['/home/docs', '/work'], reason: 'свой путь с места, где набор открыли');
    expect(theirs, isNot(contains('/home')), reason: 'шаги образца — не его шаги');

    // А у первого своя дорога цела: шага в `/work` он не делал.
    final ours = [for (final step in (await first.history()).steps) step.path];
    expect(ours, ['/home', '/home/docs']);

    await runtime.dispose();
  });

  test('закрытый набор уносит историю с собой', () async {
    final runtime = await launch();
    final app = runtime.app;

    final second = await app.openPanel(ViewportPosition.left);
    await second.session.openPath('/home/pics');
    app.closePanel(second);
    await runtime.dispose();

    final saved = await store.load();
    final paths = [
      for (final group in saved.panels)
        for (final session in group.sessions)
          for (final step in session.history) step.path,
    ];
    expect(paths, isNot(contains('/home/pics')), reason: 'шаги того, чего больше нет');
  });
}
