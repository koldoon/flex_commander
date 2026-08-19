import 'dart:convert';
import 'dart:io';

import 'package:fc_7z_archiver/fc_7z_archiver.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Упаковка выбранного в новый архив: команда `Shift-F7`.
///
/// Архив собирает программа, и на машине с тестами её нет: проверяется всё, что
/// делает модуль, — с какими ключами её зовут, из какого каталога, что лежит у
/// неё под руками и что показывает ход работы.
void main() {
  late Directory temp;
  late String root;
  late String source;
  late String target;
  late AppRuntime runtime;
  late FakeProcessRunner runner;

  /// Что программа печатает, упаковывая: имена записей и проценты.
  String packingOutput(Iterable<String> names) => [
    'Scanning the drive:',
    'Creating archive: out.7z',
    '',
    for (final name in names) '+ $name',
    'Files read from disk: ${names.length}',
    'Everything is Ok',
  ].join('\n');

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    temp = await Directory.systemTemp.createTemp('fc_7z_create');
    root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    target = p.join(root, 'target');
    await Directory(source).create();
    await Directory(target).create();

    await File(p.join(source, 'notes.txt')).writeAsString('заметки');
    await Directory(p.join(source, 'docs')).create();
    await File(p.join(source, 'docs', 'guide.txt')).writeAsString('руководство');

    runner = FakeProcessRunner(
      reply: (call) {
        if (call.command != 'a') {
          return const FakeProcessReply();
        }
        // Программа не только говорит, но и делает: без файла на месте
        // приёмника проверять доставку было бы нечего.
        final archive = call.arguments.reversed.firstWhere((argument) => argument.endsWith('.7z'));
        File(p.isAbsolute(archive) ? archive : p.join(call.workingDirectory!, archive)).writeAsStringSync('7z!');
        return FakeProcessReply(
          stdout: packingOutput(call.arguments.where((a) => !a.startsWith('-') && a != '--' && !a.endsWith('.7z'))),
        );
      },
    );

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const SevenZipArchiver()],
      processes: runner,
      settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Запускает упаковку с заданным именем — как это делает окно команды.
  Future<AppCommand> pack({String name = 'archive', SevenZipCompression? compression}) async {
    final command =
        runtime.commands.create(CreateSevenZipArchiveCommand.commandId)!
          ..setParam(CreateSevenZipArchiveCommand.nameParam, name)
          ..setParam(CreateSevenZipArchiveCommand.compressionParam, (compression ?? SevenZipCompression.normal).name);
    await command.execute();
    return command;
  }

  ProcessCall packing() => runner.callsOf('a').single;

  group('вызов программы', () {
    test('архив пишется прямо в каталог пассивной панели', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'notes');

      // Приёмник — настоящая файловая система, и второе плечо не нужно:
      // программа кладёт архив сразу на место.
      expect(packing().arguments, contains(p.join(target, 'notes.7z')));
      expect(File(p.join(target, 'notes.7z')).existsSync(), isTrue);
    });

    test('расширение дописывается само', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'notes');

      expect(packing().arguments.any((argument) => argument.endsWith('notes.7z')), isTrue);
    });

    test('имена уходят относительными, из каталога панели', () async {
      runtime.app.left.setCursorToName('docs');

      await pack(name: 'docs');

      // Настоящие пути есть — выкладывать содержимое никуда не надо, довольно
      // назвать рабочий каталог.
      expect(packing().workingDirectory, source);
      expect(packing().arguments.last, 'docs');
    });

    test('степень сжатия доходит до программы', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'best', compression: SevenZipCompression.best);

      expect(packing().arguments, contains('-mx=9'));
      expect(packing().arguments, contains('-t7z'));
    });

    test('пакуется всё помеченное, а не только объект под курсором', () async {
      runtime.app.left
        ..setCursorToName('notes.txt')
        ..toggleCurrentMark()
        ..setCursorToName('docs')
        ..toggleCurrentMark();

      await pack(name: 'both');

      expect(packing().arguments, containsAll(['notes.txt', 'docs']));
    });

    test('панель-приёмник показывает новый архив сразу', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'fresh');

      expect(runtime.app.right.nodes.map((node) => node.name), contains('fresh.7z'));
    });
  });

  group('отказы', () {
    test('занятое имя — отказ, а не молчаливая перезапись', () async {
      await File(p.join(target, 'taken.7z')).writeAsString('уже есть');
      await runtime.app.right.reload();
      runtime.app.left.setCursorToName('notes.txt');

      await expectLater(
        pack(name: 'taken'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
      );
      expect(runner.callsOf('a'), isEmpty, reason: 'звать программу незачем');
    });

    test('пустое имя — отказ', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await expectLater(
        pack(name: '  '),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
      );
    });

    test('имя с косой чертой — отказ', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await expectLater(
        pack(name: 'a/b'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
      );
    });

    test('неудача программы: полуархива на месте не остаётся', () async {
      runner = FakeProcessRunner(
        reply: (call) {
          if (call.command != 'a') {
            return const FakeProcessReply();
          }
          // Программа успела создать файл и сорвалась.
          File(call.arguments.firstWhere((argument) => argument.endsWith('.7z'))).writeAsStringSync('обрывок');
          return const FakeProcessReply(exitCode: 2, stderr: 'ERROR: disk full');
        },
      );

      runtime = await testApp(
        provider: LocalTreeProvider(homePath: root, readInIsolate: false),
        modules: [const SevenZipArchiver()],
        processes: runner,
        settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
      );
      await runtime.app.start();
      runtime.app.left.setCursorToName('notes.txt');

      await expectLater(pack(name: 'broken'), throwsA(isA<FsError>()));
      expect(File(p.join(target, 'broken.7z')).existsSync(), isFalse);
    });
  });

  group('ход работы', () {
    test('имена от программы становятся ходом работы', () async {
      runtime.app.left.setCursorToName('docs');

      final command = await pack(name: 'docs') as AsyncCommandBase;

      // Программа назвала одну запись — столько объектов и засчитано.
      expect(command.processed, greaterThan(0));
      expect(command.bytes, greaterThan(0), reason: 'размер записи берётся с диска');
    });

    test('объём работы считается по дереву источников', () async {
      runtime.app.left
        ..setCursorToName('notes.txt')
        ..toggleCurrentMark()
        ..setCursorToName('docs')
        ..toggleCurrentMark();

      final command = await pack(name: 'both') as AsyncCommandBase;

      expect(command.total, greaterThanOrEqualTo(2));
      expect(command.totalIsFinal, isTrue);
    });
  });

  test('источник без настоящего пути выкладывается на диск', () async {
    // Панель над источником, который отдаёт байты, но путей не имеет, — так
    // выглядит упаковка из другого архива.
    final memory = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/inner.txt', size: 5, content: utf8.encode('внутри')),
    ])..capabilities = archiveCapabilities;

    // Заглянуть под руку программе можно только пока она «работает»: временный
    // каталог живёт ровно до конца упаковки.
    String? staged;
    runner = FakeProcessRunner(
      reply: (call) {
        if (call.command != 'a') {
          return const FakeProcessReply();
        }
        staged = File(p.join(call.workingDirectory!, 'inner.txt')).readAsStringSync();
        File(call.arguments.firstWhere((argument) => argument.endsWith('.7z'))).writeAsStringSync('7z!');
        return const FakeProcessReply(stdout: '+ inner.txt\nEverything is Ok');
      },
    );

    runtime = await testApp(
      provider: memory,
      rightProvider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const SevenZipArchiver()],
      processes: runner,
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults(target)),
    );
    await runtime.app.start();
    runtime.app.left.setCursorToName('inner.txt');

    await pack(name: 'from_memory');

    // Содержимое выложено во временный каталог, и программу зовут оттуда.
    expect(staged, 'внутри');
    expect(packing().workingDirectory, isNot(source));
  });

  group('отмена', () {
    test('прерванная работа останавливает программу', () async {
      // Программа, которая говорит и не заканчивается: так выглядит упаковка
      // большого архива, когда пользователь передумал.
      runner = FakeProcessRunner(
        reply:
            (call) =>
                call.command == 'a'
                    ? const FakeProcessReply.running(stdout: '+ notes.txt\n+ docs/guide.txt\n')
                    : const FakeProcessReply(),
      );

      runtime = await testApp(
        provider: LocalTreeProvider(homePath: root, readInIsolate: false),
        modules: [const SevenZipArchiver()],
        processes: runner,
        settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
      );
      await runtime.app.start();
      runtime.app.left.setCursorToName('notes.txt');

      final command =
          runtime.commands.create(CreateSevenZipArchiveCommand.commandId)! as AsyncCommandBase
            ..setParam(CreateSevenZipArchiveCommand.nameParam, 'huge')
            ..setParam(CreateSevenZipArchiveCommand.compressionParam, SevenZipCompression.normal.name);

      final running = command.execute();
      // Ход работы уже пошёл — программа назвала первую запись.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      command.cancel();

      // Отмена — обычный исход, а не ошибка: команда просто заканчивается.
      await running;

      expect(runner.sessions.single.killed, isTrue, reason: 'иначе программа дописывала бы архив в никуда');
      expect(File(p.join(target, 'huge.7z')).existsSync(), isFalse);
    });
  });

  group('разбор строк программы', () {
    test('строка с плюсом называет запись', () {
      expect(sevenZipItemOf('+ docs/readme.txt'), 'docs/readme.txt');
    });

    test('строка с процентом называет её же', () {
      expect(sevenZipItemOf(' 42% 7 + docs/readme.txt'), 'docs/readme.txt');
    });

    test('имя с пробелами не обрезается', () {
      expect(sevenZipItemOf('+ мои файлы/отчёт за год.txt'), 'мои файлы/отчёт за год.txt');
    });

    test('прочие строки записями не считаются', () {
      expect(sevenZipItemOf('Everything is Ok'), isNull);
      expect(sevenZipItemOf('Files read from disk: 12'), isNull);
      expect(sevenZipItemOf(' 42%'), isNull);
      expect(sevenZipItemOf(''), isNull);
    });
  });
}
