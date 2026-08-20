import 'dart:convert';
import 'dart:io';

import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const String _listing = '''
7-Zip 24.09 (arm64) : Copyright (c) 1999-2024 Igor Pavlov

Listing archive: sample.7z

--
Path = sample.7z
Type = 7z
Physical Size = 4096

----------
Path = docs
Size = 0
Modified = 2026-08-19 10:00:00
Attributes = D_ drwxr-xr-x

Path = docs/readme.txt
Size = 12
Modified = 2026-08-19 10:01:02
Attributes = A_ -rw-r--r--

Path = .hidden
Size = 3
Attributes = A_ -rw-r--r--
''';

void main() {
  late Directory temp;
  late File archive;
  late LocalTreeProvider local;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('fc_7z_provider');
    archive = File('${temp.path}/sample.7z')..writeAsStringSync('не настоящий архив, но файл');
    local = LocalTreeProvider();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Узел архива в настоящем дереве — над ним и монтируется провайдер.
  Future<FsNode> host() async => (await local.resolvePath(archive.path).result)!;

  Future<TreeProvider> open(FakeProcessRunner runner) async {
    final provider = await SevenZipTreeProvider.open(
      await host(),
      staging: LocalStagingArea(root: temp),
      cli: SevenZipCli(processes: runner),
      credentials: FakeCredentials(),
    );
    addTearDown(() => (provider as ProviderLifecycle).dispose());
    return provider;
  }

  FakeProcessRunner listingRunner({String output = _listing}) =>
      FakeProcessRunner(reply: (call) => FakeProcessReply(stdout: call.command == 'l' ? output : ''));

  group('открытие', () {
    test('дерево строится по оглавлению', () async {
      final provider = await open(listingRunner());
      final children = await provider.getDirectoryListing(provider.rootDirectory).result;

      // «..» из корня архива ведёт наружу, к файлу архива; скрытое спрятано.
      expect(children.map((node) => node.name), ['..', 'docs']);
    });

    test('в оглавление идут обязательные ключи', () async {
      final runner = listingRunner();
      await open(runner);

      final call = runner.callsOf('l').single;
      expect(call.arguments, contains('-slt'));
      expect(call.has('-y'), isTrue, reason: 'вопросы не должны ждать ответа');
      expect(call.has('-p'), isTrue, reason: 'без пустого пароля архив с паролем подвесит работу');
      expect(call.has('--'), isTrue, reason: 'имя архива может начинаться с дефиса');
      expect(call.arguments.last, endsWith('sample.7z'));
    });

    test('без установленной программы — внятная ошибка', () async {
      final runner = FakeProcessRunner(executables: const {});

      await expectLater(
        SevenZipTreeProvider.open(
          await host(),
          staging: LocalStagingArea(root: temp),
          cli: SevenZipCli(processes: runner),
          credentials: FakeCredentials(),
        ),
        throwsA(
          isA<FsError>()
              .having((e) => e.kind, 'kind', FsErrorKind.notFound)
              .having((e) => e.message, 'message', contains('p7zip')),
        ),
      );
    });

    test('не архив — отказ открыть, а не пустой каталог', () async {
      final runner = FakeProcessRunner(
        reply:
            (call) =>
                const FakeProcessReply(exitCode: 2, stderr: 'ERROR: sample.7z : Can not open the file as archive'),
      );

      await expectLater(
        SevenZipTreeProvider.open(
          await host(),
          staging: LocalStagingArea(root: temp),
          cli: SevenZipCli(processes: runner),
          credentials: FakeCredentials(),
        ),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.io)),
      );
    });

    test('предупреждение программы не считается провалом', () async {
      final runner = FakeProcessRunner(reply: (call) => const FakeProcessReply(exitCode: 1, stdout: _listing));
      final provider = await open(runner);

      expect(await provider.listChildren(provider.rootDirectory), isNotEmpty);
    });

    test('сборка без -spd: вызов повторяется без него', () async {
      // Ключ запрета подстановок есть не везде. Программа отвечает «ошибка
      // командной строки», и второй раз её зовут без него.
      var seen = 0;
      final runner = FakeProcessRunner(
        reply: (call) {
          seen++;
          return call.has('-spd') ? const FakeProcessReply(exitCode: 7) : const FakeProcessReply(stdout: _listing);
        },
      );

      final provider = await open(runner);

      expect(seen, 2);
      expect(await provider.listChildren(provider.rootDirectory), isNotEmpty);
    });
  });

  group('чтение', () {
    test('содержимое приходит потоком', () async {
      final runner = FakeProcessRunner(
        reply:
            (call) =>
                call.command == 'l'
                    ? const FakeProcessReply(stdout: _listing)
                    : FakeProcessReply(stdoutChunks: [utf8.encode('привет, '), utf8.encode('архив')]),
      );

      final provider = await open(runner);
      final node = await provider.resolvePath('/docs/readme.txt').result;
      final bytes = await (provider as FileContentProvider).openRead(node!);

      expect(utf8.decode(await bytes.expand((chunk) => chunk).toList()), 'привет, архив');

      final call = runner.callsOf('x').single;
      expect(call.has('-so'), isTrue);
      expect(call.has('-bsp0'), isTrue, reason: 'проценты пошли бы в те же байты, что и файл');
      expect(call.arguments.last, 'docs/readme.txt');
    });

    test('чтение с середины: начало вычитывается и выбрасывается', () async {
      final runner = FakeProcessRunner(
        reply:
            (call) =>
                call.command == 'l'
                    ? const FakeProcessReply(stdout: _listing)
                    : const FakeProcessReply(
                      stdoutChunks: [
                        [1, 2, 3],
                        [4, 5, 6],
                      ],
                    ),
      );

      final provider = await open(runner);
      final node = await provider.resolvePath('/docs/readme.txt').result;
      final bytes = await (provider as FileContentProvider).openRead(node!, offset: 4);

      expect(await bytes.expand((chunk) => chunk).toList(), [5, 6]);
    });

    test('неудача программы срывает поток, а не отдаёт обрезок', () async {
      final runner = FakeProcessRunner(
        reply:
            (call) =>
                call.command == 'l'
                    ? const FakeProcessReply(stdout: _listing)
                    : const FakeProcessReply(exitCode: 2, stdout: 'начало', stderr: 'ERROR: Data Error'),
      );

      final provider = await open(runner);
      final node = await provider.resolvePath('/docs/readme.txt').result;
      final bytes = await (provider as FileContentProvider).openRead(node!);

      await expectLater(bytes.drain<void>(), throwsA(isA<FsError>()));
    });

    test('шифрованная запись: отказ до распаковки', () async {
      final runner = FakeProcessRunner(
        reply:
            (call) => const FakeProcessReply(
              stdout: '''
----------
Path = secret.txt
Size = 16
Attributes = A_ -rw-r--r--
Encrypted = +
''',
            ),
      );

      final provider = await open(runner);
      final node = await provider.resolvePath('/secret.txt').result;

      await expectLater(
        (provider as FileContentProvider).openRead(node!),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.permissionDenied)),
      );
      expect(runner.callsOf('x'), isEmpty, reason: 'звать программу незачем: пароля всё равно нет');
    });

    test('каталог содержимого не имеет', () async {
      final provider = await open(listingRunner());
      final node = await provider.resolvePath('/docs').result;

      await expectLater(
        (provider as FileContentProvider).openRead(node!),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notFound)),
      );
    });
  });

  group('дерево', () {
    test('размер и дата берутся из оглавления', () async {
      final provider = await open(listingRunner());
      final file = (await provider.resolvePath('/docs/readme.txt').result)! as FileNode;

      expect(file.size, 12);
      expect(file.modified, DateTime(2026, 8, 19, 10, 1, 2));
      expect(file.attributes.modeString, '-rw-r--r--');
    });

    test('скрытые прячутся, когда их не просят', () async {
      final provider = await open(listingRunner());
      final root = provider.rootDirectory;

      final visible = await provider.getDirectoryListing(root).result;
      final all = await provider.getDirectoryListing(root, includeHidden: true).result;

      expect(visible.map((node) => node.name), ['..', 'docs']);
      expect(all.map((node) => node.name), ['..', '.hidden', 'docs']);
    });

    test('подсчёт объектов и размера — по оглавлению, без вызовов программы', () async {
      final runner = listingRunner();
      final provider = await open(runner);
      final before = runner.calls.length;

      final root = provider.rootDirectory;
      var count = 0;
      await provider.countEntries(root, (bytes) => count++);

      expect(count, 4, reason: 'корень, docs, readme.txt и .hidden');
      expect(await provider.calculateSize([root]).result, 15);
      expect(runner.calls.length, before, reason: 'всё уже прочитано при открытии');
    });

    test('путь наружу из корня ведёт туда, где лежит архив', () async {
      final provider = await open(listingRunner());
      final listing = await provider.getDirectoryListing(provider.rootDirectory).result;

      // Провайдер смонтирован над файлом архива в чужом дереве, и «..» из
      // корня — это выход обратно в тот каталог, где архив лежит.
      expect(listing.whereType<ParentDirNode>(), hasLength(1));
      expect(provider.rootDirectory.parent?.name, 'sample.7z');
    });
  });
}
