import 'dart:convert';
import 'dart:io';

import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _listing = '''
----------
Path = docs
Size = 0
Modified = 2026-08-19 10:00:00
Attributes = D_ drwxr-xr-x

Path = docs/readme.txt
Size = 12
Modified = 2026-08-19 10:01:02
Attributes = A_ -rw-r--r--

Path = docs/inner/deep.bin
Size = 900
Modified = 2026-08-19 10:02:03
Attributes = A_ -rw-r--r--
''';

void main() {
  late Directory temp;
  late File archive;
  late LocalTreeProvider local;
  late FakeProcessRunner runner;

  /// Что ушло программе списком: команда → строки списка.
  ///
  /// Читается в момент вызова: временные файлы живут ровно до конца работы, и
  /// после неё читать было бы уже нечего.
  late Map<String, List<String>> lists;

  FakeProcessRunner runnerWith(FakeProcessReply Function(ProcessCall call) reply) {
    return FakeProcessRunner(
      reply: (call) {
        final listFile = call.arguments.where((argument) => argument.startsWith('-i@'));
        if (listFile.isNotEmpty) {
          lists[call.command] = File(listFile.first.substring(3)).readAsLinesSync();
        }
        return reply(call);
      },
    );
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fc_7z_write');
    archive = File('${temp.path}/sample.7z')..writeAsStringSync('архив');
    local = LocalTreeProvider();
    lists = {};
    runner = runnerWith((call) => FakeProcessReply(stdout: call.command == 'l' ? _listing : ''));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<WritableSevenZipTreeProvider> open() async {
    final host = (await local.resolvePath().run(archive.path))!;
    final provider =
        await SevenZipTreeProvider.open(
              host,
              staging: LocalStagingArea(root: temp),
              cli: SevenZipCli(processes: runner),
              credentials: FakeCredentials(),
            )
            as WritableSevenZipTreeProvider;
    addTearDown(provider.dispose);
    return provider;
  }

  test('архив в настоящей ФС открывается пишущим', () async {
    expect(await open(), isA<NodeEditor>());
  });

  test('запись пустого пароля не просит', () async {
    // Ключ `-p` у записи значит «зашифруй», и с пустым значением программа
    // спрашивает пароль в stdin — то есть виснет или срывается. Читающим
    // командам тот же ключ нужен, и там он значит ровно обратное.
    final provider = await open();
    await provider.createDirectory(provider.rootDirectory, 'fresh');
    await provider.deleteEntry((await provider.resolvePath().run('/docs/readme.txt'))!);

    expect(runner.callsOf('a').single.has('-p'), isFalse);
    expect(runner.callsOf('d').single.has('-p'), isFalse);
    expect(runner.callsOf('l').first.has('-p'), isTrue, reason: 'чтение без него сорвётся на архиве с паролем');
  });

  test('архив, открытый через копию, писать нельзя', () async {
    // Провайдер над архивом внутри архива: содержимое пришло потоком, и на
    // диске лежит лишь временная копия — писать в неё бессмысленно.
    // Источник, который отдаёт байты, но настоящих путей не имеет, — так
    // выглядит архив внутри архива.
    final inner = InMemoryContentProvider([FakeEntry.file('/a.7z', size: 5, content: utf8.encode('архив'))])
      ..capabilities = archiveCapabilities;
    final host = (await inner.resolvePath().run('/a.7z'))!;

    final provider = await SevenZipTreeProvider.open(
      host,
      staging: LocalStagingArea(root: temp),
      cli: SevenZipCli(processes: runner),
      credentials: FakeCredentials(),
    );
    addTearDown(() => (provider as ProviderLifecycle).dispose());

    expect(provider, isNot(isA<NodeEditor>()));
  });

  group('добавление', () {
    test('содержимое ложится по своему пути и уходит одним вызовом', () async {
      final provider = await open();
      final docs = (await provider.resolvePath().run('/docs'))! as DirectoryNode;

      final sink = await provider.openWrite(docs, 'notes.txt');
      sink.add(utf8.encode('заметки'));
      await sink.close();

      final call = runner.callsOf('a').single;
      expect(lists['a'], ['docs/notes.txt'], reason: 'имя записи — это относительный путь в рабочем каталоге');
      expect(call.workingDirectory, isNotNull);
      expect(File(p.join(call.workingDirectory!, 'docs/notes.txt')).readAsStringSync(), 'заметки');
      expect(call.arguments, contains('-t7z'));
      expect(call.has('-scsUTF-8'), isTrue, reason: 'иначе имя с кириллицей не дойдёт до программы');

      // Список — ключом, а не аргументом: после `--` программа приняла бы
      // `@файл` за имя файла с именем `@`.
      expect(call.arguments.any((argument) => argument.startsWith('-i@')), isTrue);
      expect(
        call.arguments.indexWhere((argument) => argument.startsWith('-i@')),
        lessThan(call.arguments.indexOf('--')),
      );
    });

    test('панель видит запись сразу, не дожидаясь программы', () async {
      final provider = await open();

      // Внутри работы: программу ещё не звали, а панель уже должна показывать
      // то, что в архив кладут, — иначе копирование выглядит бездействием.
      await provider.beginWrites(FakeOperationContext());
      final sink = await provider.openWrite(provider.rootDirectory, 'added.txt');
      sink.add(utf8.encode('12345'));
      await sink.close();

      final node = await provider.resolvePath().run('/added.txt');
      expect((node! as FileNode).size, 5);

      await provider.endWrites(FakeOperationContext());
    });

    test('после работы дерево берётся у программы, а не из своих догадок', () async {
      // Программа могла записать не то, что от неё ждали: часть файлов
      // пропустить, имя изменить. Верно то, что она сама и показывает.
      runner = runnerWith(
        (call) => FakeProcessReply(
          stdout:
              call.command != 'l'
                  ? ''
                  : (runner.callsOf('a').isEmpty
                      ? _listing
                      : '$_listing\nPath = added.txt\nSize = 5\nAttributes = A_ -rw-r--r--\n'),
        ),
      );

      final provider = await open();
      final sink = await provider.openWrite(provider.rootDirectory, 'added.txt');
      sink.add(utf8.encode('12345'));
      await sink.close();

      expect(await provider.resolvePath().run('/added.txt'), isNotNull);
    });

    test('пустой каталог заводится настоящим пустым каталогом', () async {
      final provider = await open();

      await provider.createDirectory(provider.rootDirectory, 'empty');

      final call = runner.callsOf('a').single;
      expect(lists['a'], ['empty']);
      expect(Directory(p.join(call.workingDirectory!, 'empty')).existsSync(), isTrue);
    });

    test('занятое имя каталога — отказ', () async {
      final provider = await open();

      await expectLater(
        provider.createDirectory(provider.rootDirectory, 'docs'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
      );
    });
  });

  group('удаление', () {
    test('запись удаляется по точному имени', () async {
      final provider = await open();
      final node = (await provider.resolvePath().run('/docs/readme.txt'))!;

      await provider.deleteEntry(node);

      expect(runner.callsOf('d'), hasLength(1));
      expect(lists['d'], ['docs/readme.txt']);
    });

    test('поддерево перечисляется целиком, без подстановок', () async {
      final provider = await open();
      final node = (await provider.resolvePath().run('/docs'))!;

      await provider.deleteTree(node);

      // Имена все известны — оглавление прочитано, и полагаться на подстановку,
      // которой в сборке может не быть, незачем. Каталога `docs/inner` в
      // списке нет: в архиве его записью не объявляли, он достроен по пути, и
      // удалять программе нечего.
      expect(lists['d']!..sort(), ['docs', 'docs/inner/deep.bin', 'docs/readme.txt']);
    });

    test('удалённое исчезает из панели сразу', () async {
      final provider = await open();

      await provider.beginWrites(FakeOperationContext());
      await provider.deleteEntry((await provider.resolvePath().run('/docs/readme.txt'))!);

      expect(await provider.resolvePath().run('/docs/readme.txt'), isNull);

      await provider.endWrites(FakeOperationContext());
    });
  });

  group('пачка', () {
    test('внутри работы программа не зовётся, в конце — один раз', () async {
      final provider = await open();
      final root = provider.rootDirectory;

      await provider.beginWrites(FakeOperationContext());
      for (final name in ['one.txt', 'two.txt', 'three.txt']) {
        final sink = await provider.openWrite(root, name);
        sink.add(utf8.encode(name));
        await sink.close();
      }
      expect(runner.callsOf('a'), isEmpty, reason: 'работа ещё идёт');

      await provider.endWrites(FakeOperationContext());

      expect(runner.callsOf('a'), hasLength(1));
      expect(lists['a']!..sort(), ['one.txt', 'three.txt', 'two.txt']);
    });

    test('удаление и добавление в одной пачке: сперва удаления', () async {
      final provider = await open();

      await provider.beginWrites(FakeOperationContext());
      await provider.deleteEntry((await provider.resolvePath().run('/docs/readme.txt'))!);
      final sink = await provider.openWrite(provider.rootDirectory, 'new.txt');
      sink.add(utf8.encode('новое'));
      await sink.close();
      await provider.endWrites(FakeOperationContext());

      final calls = runner.calls.map((call) => call.command).where((command) => command == 'a' || command == 'd');
      expect(calls, ['d', 'a']);
    });

    test('вложенные границы работы: программа зовётся на самой внешней', () async {
      final provider = await open();

      await provider.beginWrites(FakeOperationContext());
      await provider.beginWrites(FakeOperationContext());
      final sink = await provider.openWrite(provider.rootDirectory, 'one.txt');
      sink.add(utf8.encode('1'));
      await sink.close();
      await provider.endWrites(FakeOperationContext());
      expect(runner.callsOf('a'), isEmpty);

      await provider.endWrites(FakeOperationContext());
      expect(runner.callsOf('a'), hasLength(1));
    });

    test('оглавление перечитывается после записи', () async {
      final provider = await open();
      final before = runner.callsOf('l').length;

      await provider.createDirectory(provider.rootDirectory, 'fresh');

      expect(runner.callsOf('l').length, before + 1, reason: 'после записи архив уже не тот, что был');
    });

    test('неудача программы не оставляет дерево, которого нет', () async {
      runner = runnerWith(
        (call) => switch (call.command) {
          'l' => const FakeProcessReply(stdout: _listing),
          'a' => const FakeProcessReply(exitCode: 2, stderr: 'ERROR: disk full'),
          _ => const FakeProcessReply(),
        },
      );

      final provider = await open();
      final sink = await provider.openWrite(provider.rootDirectory, 'doomed.txt');
      sink.add(utf8.encode('...'));

      await expectLater(sink.close(), throwsA(isA<FsError>()));

      // Оглавление перечитано, и записи, которой программа не сделала, в
      // панели нет — иначе пользователь смотрел бы на несуществующий файл.
      expect(await provider.resolvePath().run('/doomed.txt'), isNull);
    });
  });

  test('незаписанное дописывается при закрытии панели', () async {
    final host = (await local.resolvePath().run(archive.path))!;
    final provider =
        await SevenZipTreeProvider.open(
              host,
              staging: LocalStagingArea(root: temp),
              cli: SevenZipCli(processes: runner),
              credentials: FakeCredentials(),
            )
            as WritableSevenZipTreeProvider;

    await provider.beginWrites(FakeOperationContext());
    final sink = await provider.openWrite(provider.rootDirectory, 'last.txt');
    sink.add(utf8.encode('не пропади'));
    await sink.close();

    await provider.dispose();

    expect(runner.callsOf('a'), hasLength(1));
    expect(lists['a'], ['last.txt']);
  });
}
