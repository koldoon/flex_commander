import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// Команда должна работать и без интерфейса: задать параметры и выполнить.
/// Именно так её вызовут меню, сценарий или командная строка.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
    await app.start();
  });

  CommandService commands() => app.commands;

  MakeDirectoryCommand makeDirectory() => commands().create('file.mkdir')! as MakeDirectoryCommand;

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  test('создаёт каталог по заданному параметру', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.execute();

    expect(namesOf(), contains('docs'));
  });

  test('курсор встаёт на созданный каталог', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.execute();

    expect(app.left.currentNode?.name, 'docs');
  });

  test('лишние пробелы в имени отбрасываются', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, '  docs  ');

    await command.execute();

    expect(namesOf(), contains('docs'));
  });

  test('пустое имя — ошибка в окне, а не молчаливый отказ', () async {
    // Проверка имени переехала туда, где она нужна: имени нет — значит его
    // спрашивают, а ошибка появляется, когда его так и не набрали.
    var created = false;
    final state = MakeDirectoryDialogState(parentPath: '/home', create: (name) async => created = true)..name = '   ';

    await state.submit();

    expect(created, isFalse);
    expect(state.error, const FsError('', FsErrorKind.invalidName).message);
  });

  test('существующее имя даёт ошибку', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'bin');

    await expectLater(
      command.execute(),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('каталог создаётся в активной панели', () async {
    app.toggleActivePanel();
    await app.right.openPath('/home/bin');

    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'tools');
    await command.execute();

    expect(app.right.nodes.map((node) => node.name), contains('tools'));
    expect(namesOf(), isNot(contains('tools')));
  });

  test('подтверждение выполняет команду и закрывает окно', () async {
    // Так это делает ядро по Enter: параметры уже заданы, остаётся выполнить.
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.submit();

    expect(namesOf(), contains('docs'));
    expect(command.error, isNull);
  });

  test('ошибка остаётся в команде, а не улетает наружу', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'bin');

    // submit — общее поведение ядра: ошибку показывает окно, поэтому наружу
    // она не выбрасывается.
    await command.submit();

    expect(command.error, contains('Already exists'));
  });

  test('команда доступна и закреплена за клавишей', () {
    final command = commands().find('file.mkdir')!;

    expect(command.label, 'Mk Dir');
    expect(commands().isExecutable(command), isTrue);
    expect(commands().bindingsOf('file.mkdir').map((b) => b.keys.toString()), contains('F7'));
  });
}
