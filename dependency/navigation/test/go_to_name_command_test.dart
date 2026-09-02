import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переход к имени: символ — обычный параметр команды, поэтому проверять её
/// можно без клавиатуры.
void main() {
  late InMemoryTreeProvider provider;
  late Application app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/downloads'),
      FakeEntry.file('/home/data.csv', size: 10),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/Report.pdf', size: 20),
    ]);
    final runtime = await testApp(
      provider: provider,
      modules: [const Navigation()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    app = runtime.app;
    await app.start();
  });

  CommandService commands() => app.commands;

  Future<void> goTo(String character) async {
    final command = commands().create('panel.goToName')!;
    await command.executeWith({GoToNameCommand.characterParam: character});
  }

  String? cursorName() => app.left.currentEntry?.name;

  test('курсор встаёт на первое имя с этой буквы', () async {
    await goTo('n');

    expect(cursorName(), 'notes.txt');
  });

  test('регистр не важен', () async {
    await goTo('r');

    expect(cursorName(), 'Report.pdf');
  });

  test('повторное нажатие переходит к следующему такому имени', () async {
    await goTo('d');
    expect(cursorName(), 'docs');

    await goTo('d');
    expect(cursorName(), 'downloads');

    await goTo('d');
    expect(cursorName(), 'data.csv');

    // По кругу: после последнего снова первое.
    await goTo('d');
    expect(cursorName(), 'docs');
  });

  test('если такого имени нет, курсор остаётся на месте', () async {
    app.left.setCursorToName('notes.txt');

    await goTo('z');

    expect(cursorName(), 'notes.txt');
  });

  test('«..» именем не считается', () async {
    app.left.setCursorToName('notes.txt');

    await goTo('.');

    expect(cursorName(), 'notes.txt');
  });

  test('работает в активной панели, а не всегда в левой', () async {
    app.toggleActivePanel();

    await goTo('n');

    expect(app.right.currentEntry?.name, 'notes.txt');
    expect(app.left.cursorIndex, 0);
  });

  test('без символа команда ничего не делает', () async {
    app.left.setCursorToName('notes.txt');

    await commands().create('panel.goToName')!.executeWith();

    expect(cursorName(), 'notes.txt');
  });

  test('команда видна в списке команд', () {
    expect(commands().find('panel.goToName')?.label, 'Go to name');
  });
}
