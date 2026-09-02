import 'dart:convert';
import 'dart:io';

import 'package:fc_7z/backend.dart';
import 'package:fc_7z/frontend.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:fc_local_fs/backend.dart';
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

  /// Что ушло программе списком имён.
  late List<String> packedNames;

  /// Имена из списка, который назвали ключом `-i@`.
  List<String> listOf(ProcessCall call) {
    final listFile = call.arguments.firstWhere((argument) => argument.startsWith('-i@'), orElse: () => '');
    return listFile.isEmpty ? const [] : File(listFile.substring(3)).readAsLinesSync();
  }

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

    packedNames = <String>[];
    runner = FakeProcessRunner(
      reply: (call) {
        if (call.command != 'a') {
          return const FakeProcessReply();
        }
        // Программа не только говорит, но и делает: без файла на месте
        // приёмника проверять доставку было бы нечего.
        final archive = call.arguments.reversed.firstWhere((argument) => argument.endsWith('.7z'));
        File(p.isAbsolute(archive) ? archive : p.join(call.workingDirectory!, archive)).writeAsStringSync('7z!');
        // Список читается сейчас: временный каталог живёт до конца работы.
        packedNames = listOf(call);
        return FakeProcessReply(stdout: packingOutput(packedNames));
      },
    );

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const SevenZipArchiverFrontend()],
      backend: [const SevenZipArchiverBackend()],
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
    final command = runtime.commands.create(CreateSevenZipArchiveCommand.commandId)!;
    await command.executeWith({
      CreateSevenZipArchiveCommand.nameParam: name,
      CreateSevenZipArchiveCommand.compressionParam: (compression ?? SevenZipCompression.normal).name,
    });
    return command;
  }

  ProcessCall packing() => runner.callsOf('a').single;

  /// Ход работы — свойство самой операции, а не команды: команда показывает
  /// окно и уходит. Поэтому проверяется операция.
  Future<Operation<Object?, void>> packed(String name) async {
    final command = runtime.commands.create(CreateSevenZipArchiveCommand.commandId)! as CreateSevenZipArchiveCommand;
    final panel = runtime.app.left;
    final sources =
        panel.selection.isEmpty ? [panel.currentNode!] : panel.nodes.where(panel.selection.contains).toList();

    final operation =
        command.packOperation()..start(
          SevenZipPackParams(
            sources,
            runtime.app.right.directory!,
            '$name.7z',
            compression: SevenZipCompression.normal,
            followLinks: false,
          ),
        );
    await operation.result;
    return operation;
  }

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
      expect(packedNames, ['docs']);
    });

    test('степень сжатия доходит до программы', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'best', compression: SevenZipCompression.best);

      expect(packing().arguments, contains('-mx=9'));
      expect(packing().arguments, contains('-t7z'));
    });

    test('пароля упаковка не просит', () async {
      // `-p` у записи значит «зашифруй», и с пустым значением программа
      // спрашивает пароль в stdin: работа срывается на ровном месте.
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'plain');

      expect(packing().has('-p'), isFalse);
    });

    test('имена уходят списком, а не аргументами', () async {
      // Помеченных может быть тысячи: командная строка такой длины не бывает.
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'listed');

      final arguments = packing().arguments;
      expect(arguments.any((argument) => argument.startsWith('-i@')), isTrue);
      expect(arguments.indexWhere((argument) => argument.startsWith('-i@')), lessThan(arguments.indexOf('--')));
      expect(arguments.last, endsWith('listed.7z'), reason: 'после `--` остаётся только путь архива');
    });

    test('пакуется всё помеченное, а не только объект под курсором', () async {
      runtime.app.left
        ..setCursorToName('notes.txt')
        ..toggleCurrentMark()
        ..setCursorToName('docs')
        ..toggleCurrentMark();

      await pack(name: 'both');

      expect(packedNames..sort(), ['docs', 'notes.txt']);
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
        modules: [const SevenZipArchiverFrontend()],
        backend: [const SevenZipArchiverBackend()],
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

      final status = (await packed('docs')).status as MultipleTransferOperationStatus;

      // Программа назвала одну запись — столько объектов и засчитано.
      expect(status.itemsTransferred, greaterThan(0));
      expect(status.bytesTransferred, greaterThan(0), reason: 'размер записи берётся с диска');
    });

    test('объём работы считается по дереву источников', () async {
      runtime.app.left
        ..setCursorToName('notes.txt')
        ..toggleCurrentMark()
        ..setCursorToName('docs')
        ..toggleCurrentMark();

      final status = (await packed('both')).status as MultipleTransferOperationStatus;

      expect(status.itemsTotal, greaterThanOrEqualTo(2));
      expect(status.totalIsFinal, isTrue);
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
    packedNames = <String>[];
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
      modules: [const SevenZipArchiverFrontend()],
      backend: [const SevenZipArchiverBackend()],
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
        modules: [const SevenZipArchiverFrontend()],
        backend: [const SevenZipArchiverBackend()],
        processes: runner,
        settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
      );
      await runtime.app.start();
      runtime.app.left.setCursorToName('notes.txt');

      // Прерывают саму работу, а не команду: команда показала окно и ушла.
      final command = runtime.commands.create(CreateSevenZipArchiveCommand.commandId)! as CreateSevenZipArchiveCommand;
      final operation =
          command.packOperation()..start(
            SevenZipPackParams(
              [runtime.app.left.currentNode!],
              runtime.app.right.directory!,
              'huge.7z',
              compression: SevenZipCompression.normal,
              followLinks: false,
            ),
          );

      // Ход работы уже пошёл — программа назвала первую запись.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Просьба прервать, а не жёсткая отмена: так делает Esc в окне, и именно
      // она доходит до программы через контрольную точку.
      operation.requestCancel();

      // Отмена — обычный исход, а не ошибка: работа просто заканчивается.
      await operation.result.catchError((Object _) {});

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
