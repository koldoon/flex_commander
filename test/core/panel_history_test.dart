import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// История переходов живой сессии: что в неё попадает и как по ней ходят
/// (`docs/spec/session-history.md`).
void main() {
  late InMemoryTreeProvider provider;

  PanelSession sessionFor(PanelSettings settings, {int Function()? limit}) => PanelSession(
    settings: settings,
    registry: ProviderRegistry(root: provider),
    editor: const TreeTransferEngine(),
    historyLimit: limit ?? () => 50,
  );

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/pics'),
      FakeEntry.file('/home/docs/deep.txt', size: 40),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ])..home = '/home';
  });

  /// Пути шагов по порядку.
  List<String> pathsOf(PanelSession session) => [for (final step in session.history.steps) step.path];

  test('пройденное записывается, и назад возвращает по шагам', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.openPath('/home/docs');
    await session.openPath('/home/pics');

    expect(pathsOf(session), ['/home', '/home/docs', '/home/pics']);
    expect(session.canGoBack, isTrue);
    expect(session.canGoForward, isFalse);

    await session.goBack();
    expect(session.currentPath, '/home/docs');
    await session.goBack();
    expect(session.currentPath, '/home');
    expect(session.canGoBack, isFalse);

    await session.goForward();
    expect(session.currentPath, '/home/docs');
  });

  test('шаг назад сам в историю не пишется', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.openPath('/home/docs');
    await session.goBack();

    expect(pathsOf(session), ['/home', '/home/docs'], reason: 'возврат добавил шаг');
  });

  test('возврат ставит курсор туда, где он стоял', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    session.setCursorToName('report.txt');
    expect(session.currentNode?.name, 'report.txt');

    await session.openPath('/home/docs');
    await session.goBack();

    expect(session.currentPath, '/home');
    expect(session.currentNode?.name, 'report.txt', reason: 'шаг отменён наполовину: каталог тот, место потеряно');
  });

  test('перечитывание шага не добавляет', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.reload();
    await session.reload();

    expect(pathsOf(session), ['/home'], reason: 'перечитывание — не перемещение');
  });

  test('неудавшийся путь в историю не попадает', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');

    expect(await session.openPath('/home/nowhere'), isFalse);
    expect(pathsOf(session), ['/home']);
  });

  test('подъём наверх — такой же шаг', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home/docs');
    await session.goUp();

    expect(pathsOf(session), ['/home/docs', '/home']);
    expect(session.currentPath, '/home');
  });

  test('новый переход после возврата обрезает «вперёд»', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.openPath('/home/docs');
    await session.goBack();
    await session.openPath('/home/pics');

    expect(pathsOf(session), ['/home', '/home/pics']);
    expect(session.canGoForward, isFalse);
  });

  test('прыжок к шагу «вперёд» не обрезает', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.openPath('/home/docs');
    await session.openPath('/home/pics');

    await session.goToStep(0);

    expect(session.currentPath, '/home');
    expect(pathsOf(session), ['/home', '/home/docs', '/home/pics']);
    expect(session.canGoForward, isTrue);
  });

  test('предел вытесняет самый старый шаг', () async {
    final session = sessionFor(PanelSettings.defaults('/home'), limit: () => 2);
    await session.openPath('/home');
    await session.openPath('/home/docs');
    await session.openPath('/home/pics');

    expect(pathsOf(session), ['/home/docs', '/home/pics']);
  });

  test('история уходит в настройки и поднимается из них', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    session.setCursorToName('notes.txt');
    await session.openPath('/home/docs');
    await session.goBack();

    final saved = session.settings;
    expect([for (final step in saved.history) step.path], ['/home', '/home/docs']);
    expect(saved.historyIndex, 0, reason: 'закрыли, вернувшись на шаг назад');

    // Новый запуск из тех же настроек: «вперёд» ведёт туда же, куда вело бы.
    final restored = sessionFor(saved);
    await restored.openPath(saved.path);

    expect(restored.canGoForward, isTrue);
    await restored.goForward();
    expect(restored.currentPath, '/home/docs');
  });

  test('состояние для той стороны несёт оба флага', () async {
    final session = sessionFor(PanelSettings.defaults('/home'));
    await session.openPath('/home');
    await session.openPath('/home/docs');

    expect(session.state.canGoBack, isTrue);
    expect(session.state.canGoForward, isFalse);

    await session.goBack();

    expect(session.state.canGoBack, isFalse);
    expect(session.state.canGoForward, isTrue);
  });
}
