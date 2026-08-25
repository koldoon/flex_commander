import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Копирование и перенос работают без интерфейса: задать параметр и выполнить.
/// Окно — надстройка, и его в этих тестах нет.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/readme.md', size: 5),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.directory('/backup'),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/backup'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
    await app.start();
  });

  CommandService commands() => app.commands;

  /// Приёмник задаётся сразу: у теста окна нет, а путь по умолчанию
  /// подставляет именно оно. Проверка самой подстановки — в виджетном тесте
  /// «F5 открывает окно с каталогом пассивной панели».
  Future<void> transfer({bool move = false, String? destination, bool followLinks = false}) =>
      commands().create(move ? 'file.move' : 'file.copy')!.executeWith({
        TransferCommandBase.destinationParam: destination ?? app.right.directory!.pathString,
        if (followLinks) TransferCommandBase.followLinksParam: true,
      });

  List<String> namesOf(PanelController panel) => panel.nodes.map((node) => node.name).toList();

  test('копирует в каталог пассивной панели', () async {
    app.left.setCursorToName('notes.txt');
    await transfer();

    expect(namesOf(app.right), contains('notes.txt'));
    expect(namesOf(app.left), contains('notes.txt'));
  });

  test('перенос убирает объект из источника', () async {
    app.left.setCursorToName('notes.txt');

    await transfer(move: true);

    expect(namesOf(app.left), isNot(contains('notes.txt')));
    expect(namesOf(app.right), contains('notes.txt'));
  });

  test('работает со всеми помеченными объектами', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    await transfer();

    expect(namesOf(app.right), containsAll(['notes.txt', 'report.xlsx']));
    expect(namesOf(app.right), isNot(contains('docs')));
  });

  test('каталог копируется вместе с содержимым', () async {
    app.left.setCursorToName('docs');

    await transfer();

    final copied = await provider.resolvePath().run('/backup/docs/readme.md');
    expect(copied, isNotNull);
  });

  test('приёмник задаётся параметром, а не панелью', () async {
    app.left.setCursorToName('notes.txt');
    await transfer(destination: '/home/docs');

    expect(await provider.resolvePath().run('/home/docs/notes.txt'), isNotNull);
    expect(namesOf(app.right), isNot(contains('notes.txt')));
  });

  test('несуществующий приёмник — ошибка', () async {
    app.left.setCursorToName('notes.txt');
    await expectLater(transfer(destination: '/nowhere'), throwsA(isA<FsError>()));
  });

  test('приёмник-файл — ошибка', () async {
    app.left.setCursorToName('notes.txt');
    await expectLater(
      transfer(destination: '/home/report.xlsx'),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notADirectory)),
    );
  });

  test('пустой приёмник — ошибка, а не молчаливый отказ', () async {
    app.left.setCursorToName('notes.txt');

    // Пробелы — это заданный приёмник, просто негодный: спрашивать заново
    // нечего, надо сказать, что он не годится. В окне та же ошибка остаётся
    // в нём самом — это проверяет виджетный тест.
    await expectLater(
      transfer(destination: '   '),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
    );
  });

  test('без окна вопрос о совпадении имён решается сам собой', () async {
    provider.add(FakeEntry.file('/backup/notes.txt', size: 1));
    await app.right.reload();
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    // Спросить некого: существующий файл пропускается, работа продолжается.
    await transfer();

    expect(namesOf(app.right), containsAll(['notes.txt', 'report.xlsx']));
  });

  test('после работы пометка снята, обе панели перечитаны', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    await transfer(move: true);

    expect(app.left.selection.isEmpty, isTrue);
    expect(namesOf(app.left), isNot(contains('notes.txt')));
    expect(namesOf(app.right), contains('notes.txt'));
  });

  test('работа доходит до конца и без окна', () async {
    // Ход работы рассказывает прогон, а он живёт в окне; здесь окна нет —
    // приёмник задан параметром, и команда работает напрямую.
    app.left.setCursorToName('notes.txt');

    await transfer();

    expect(namesOf(app.right), contains('notes.txt'));
  });

  test('на «..» команда недоступна', () {
    app.left.setCursorToFirst();

    expect(commands().isExecutable(commands().find('file.copy')!), isFalse);
    expect(commands().isExecutable(commands().find('file.move')!), isFalse);
  });

  group('символические ссылки', () {
    setUp(() async {
      provider.add(FakeEntry.link('/home/shortcut', '/home/docs'));
      // Панель прочитала каталог при запуске — новый объект она увидит только
      // после перечитывания.
      await app.left.reload();
    });

    test('по умолчанию по ссылкам не идём — как в mc: в приёмнике ссылка, а не копия каталога', () async {
      app.left.setCursorToName('shortcut');

      // Значения нет вовсе — и это значит «не следовать».
      await transfer();

      final copied = await provider.resolvePath().run('/backup/shortcut');
      expect(copied, isA<LinkNode>());
    });

    test('следуем — в приёмнике оказывается содержимое цели', () async {
      app.left.setCursorToName('shortcut');
      await transfer(followLinks: true);

      // Пошли по ссылке: скопировался каталог, на который она указывает.
      expect(await provider.resolvePath().run('/backup/shortcut/readme.md'), isNotNull);
    });
  });

  group('источник только для чтения', () {
    /// Левая панель — архив, открытый на просмотр: дерево и содержимое есть,
    /// менять нечем. Правая — обычный диск.
    Future<AppController> openArchive(InMemoryReadOnlyProvider archive) async {
      // Приёмник умеет принимать байты — иначе потоку не во что литься.
      final disk = InMemoryContentProvider([FakeEntry.directory('/backup')]);
      final settings = AppSettings(left: PanelSettings.defaults('/arc'), right: PanelSettings.defaults('/backup'));
      final it =
          (await testApp(
            provider: archive,
            rightProvider: disk,
            modules: [const Navigation(), const FileOps()],
            settings: settings,
          )).app;
      await it.start();
      it.left.setCursorToName('inside.txt');
      return it;
    }

    List<FakeEntry> entries() => [
      FakeEntry.directory('/arc'),
      FakeEntry.file('/arc/inside.txt', content: [1, 2, 3]),
    ];

    test('копировать из него можно: принимает приёмник, а не источник', () async {
      final app = await openArchive(InMemoryArchiveProvider(entries()));

      expect(app.commands.isExecutable(app.commands.find('file.copy')!), isTrue);
      // Перенос убрал бы объект из архива, а убирать в нём нечем.
      expect(app.commands.isExecutable(app.commands.find('file.move')!), isFalse);
    });

    test('копирование доходит до приёмника потоком', () async {
      final app = await openArchive(InMemoryArchiveProvider(entries()));

      await app.commands.create('file.copy')!.executeWith({'destination': '/backup'});

      expect(app.right.nodes.map((node) => node.name), contains('inside.txt'));
    });

    test('без содержимого копировать нечем, и команда об этом не врёт', () async {
      // Дерево есть, байтов нет: взять файл неоткуда.
      final app = await openArchive(InMemoryReadOnlyProvider(entries()));

      await app.commands.create('file.copy')!.executeWith({'destination': '/backup'});

      expect(app.right.nodes.map((node) => node.name), isNot(contains('inside.txt')));
    });
  });

  test('обе команды видны в списке команд и закреплены за клавишами', () {
    expect(commands().find('file.copy')?.label, 'Copy');
    expect(commands().find('file.move')?.label, 'Move');
    expect(commands().bindingsOf('file.copy').map((b) => b.keys.toString()), contains('F5'));
    expect(commands().bindingsOf('file.move').map((b) => b.keys.toString()), contains('F6'));
  });
}
