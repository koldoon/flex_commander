import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// Удаление тоже должно работать без интерфейса: подтверждение — дело окна,
/// а execute просто удаляет.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
    await app.start();
  });

  CommandService commands() => app.commands;

  /// Согласие задаётся сразу: у теста окна нет, а спрашивать некого.
  RemoveCommandBase remove({bool permanently = false}) =>
      commands().create(permanently ? 'file.removePermanently' : 'file.remove')! as RemoveCommandBase
        ..setParam(RemoveCommandBase.confirmedParam, true);

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  test('удаляет объект под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await remove().execute();

    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('удаляет все помеченные объекты', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    await remove().execute();

    expect(namesOf(), isNot(contains('notes.txt')));
    expect(namesOf(), isNot(contains('report.xlsx')));
    expect(namesOf(), contains('docs'));
  });

  test('после удаления пометка снята', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    await remove().execute();

    expect(app.left.selection.isEmpty, isTrue);
  });

  test('на «..» команда недоступна', () {
    app.left.setCursorToFirst();

    expect(commands().isExecutable(commands().find('file.remove')!), isFalse);
  });

  test('без окна вопрос по ошибке решается сам собой', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();
    // Объект исчез уже после того, как панель его показала.
    provider.removeEntry('/home/notes.txt');

    // Спросить некого — операция берёт ответ по умолчанию и идёт дальше.
    await remove().execute();

    expect(namesOf(), isNot(contains('report.xlsx')));
  });

  test('о ходе работы рассказывает прогон, а не команда', () async {
    // Ход работы, подтверждение и отмена принадлежат окну: команда показывает
    // его и уходит. Проверяется поэтому прогон.
    final run = FcAsyncRun(
      app: app,
      commandId: 'file.remove',
      title: 'Delete',
      failureMessage: 'Delete failed',
      show: () {},
    );

    app.left.setCursorToName('notes.txt');
    final node = app.left.currentNode!;
    final done = run.run(app.left.editor!.remove([node]), message: 'Deleting…');

    expect(run.isRunning, isTrue);
    await done;

    expect(run.isRunning, isFalse);
    expect(run.progressMessage, isNotEmpty);
  });

  test('пока прогон идёт, подтверждение и отмена не срабатывают', () async {
    final run = FcAsyncRun(
      app: app,
      commandId: 'file.remove',
      title: 'Delete',
      failureMessage: 'Delete failed',
      show: () {},
    );
    var started = 0;
    run.onStart = () async => started++;

    app.left.setCursorToName('notes.txt');
    final node = app.left.currentNode!;
    final running = run.run(app.left.editor!.remove([node]), message: 'Deleting…');
    expect(run.isRunning, isTrue);

    // Рама окна зовёт эти методы по Enter и Esc — во время работы они молчат.
    await run.submit();
    run.dismiss();

    expect(started, 0, reason: 'работа уже идёт, запускать нечего');

    await running;
    // Перечитывает панель тот, кто заводил работу; здесь её завёл тест.
    await app.left.reload();
    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('обе команды видны в списке команд', () {
    expect(commands().find('file.remove')?.label, 'Delete');
    expect(commands().find('file.removePermanently')?.label, 'Delete !');
    expect(commands().bindingsOf('file.remove').map((b) => b.keys.toString()), contains('F8'));
    expect(commands().bindingsOf('file.removePermanently').map((b) => b.keys.toString()), contains('Shift-F8'));
  });
}
