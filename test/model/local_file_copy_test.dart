import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Копия файла средствами системы: `copyfile(3)` через FFI.
///
/// Проверяется здесь то, чего не видно ни в движке, ни в провайдере: что копия
/// побайтово та же, что метаданные на месте, что байты идут по ходу дела и что
/// отмена доходит внутрь файла. Ошибка в этом слое роняет процесс, а не бросает
/// исключение, — поэтому и констант это касается тоже.
void main() {
  late Directory temp;
  late String root;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_copy');
    root = await temp.resolveSymbolicLinks();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Файл заданного размера со случайным началом: побайтовое сравнение на
  /// сплошных нулях ничего не значит.
  Future<String> makeFile(String name, int size) async {
    final path = p.join(root, name);
    final bytes = Uint8List(size);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 31 + 7) & 0xFF;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  group('константы copyfile.h', () {
    /// Заголовок SDK — единственное, с чем эти числа можно сличить.
    ///
    /// Разбираются и `(1<<N)`, и десятичные значения: в заголовке есть и то,
    /// и другое.
    Map<String, int>? headerDefines() {
      final sdk = Process.runSync('xcrun', ['--show-sdk-path']);
      if (sdk.exitCode != 0) {
        return null;
      }
      final header = File(p.join((sdk.stdout as String).trim(), 'usr', 'include', 'copyfile.h'));
      if (!header.existsSync()) {
        return null;
      }

      final defines = <String, int>{};
      final pattern = RegExp(r'^#define\s+(COPYFILE_\w+)\s+(?:\(1<<(\d+)\)|(\d+))\s*(?:/\*.*)?$');
      for (final line in header.readAsLinesSync()) {
        final match = pattern.firstMatch(line.trim());
        if (match == null) {
          continue;
        }
        final shift = match.group(2);
        defines[match.group(1)!] = shift != null ? 1 << int.parse(shift) : int.parse(match.group(3)!);
      }
      return defines;
    }

    test('сходятся с заголовком SDK', () {
      final defines = headerDefines();
      if (defines == null) {
        // Без Xcode сличать не с чем: остаются проверки поведением ниже.
        markTestSkipped('заголовок copyfile.h не найден');
        return;
      }

      expect(
        copyfileAll,
        defines['COPYFILE_ACL']! | defines['COPYFILE_STAT']! | defines['COPYFILE_XATTR']! | defines['COPYFILE_DATA']!,
      );
      expect(copyfileStateStatusCb, defines['COPYFILE_STATE_STATUS_CB']);
      expect(copyfileStateCopied, defines['COPYFILE_STATE_COPIED']);
      expect(copyfileCopyData, defines['COPYFILE_COPY_DATA']);
      expect(copyfileFinish, defines['COPYFILE_FINISH']);
      expect(copyfileProgress, defines['COPYFILE_PROGRESS']);
      expect(copyfileContinue, defines['COPYFILE_CONTINUE']);
      expect(copyfileQuit, defines['COPYFILE_QUIT']);
    });
  });

  group('копия', () {
    test('система умеет копировать с ходом работы', () {
      // Не умеет — всё остальное здесь проверять нечего, и провайдер сам
      // останется на `File.copy`.
      expect(systemFileCopyAvailable, Platform.isMacOS);
    }, skip: !Platform.isMacOS);

    test('побайтово равна источнику', () async {
      final source = await makeFile('source.bin', 3 * 1024 * 1024);
      final target = p.join(root, 'target.bin');

      await copyFileWithProgress(source, target, (bytes) => true);

      expect(await File(target).readAsBytes(), await File(source).readAsBytes());
    });

    test('дата и права остаются теми же', () async {
      final source = await makeFile('source.bin', 1024);
      final target = p.join(root, 'target.bin');
      await Process.run('chmod', ['640', source]);
      final modified = DateTime(2020, 5, 17, 13, 45, 12);
      File(source).setLastModifiedSync(modified);

      await copyFileWithProgress(source, target, (bytes) => true);

      final stat = File(target).statSync();
      // Ради этого копия и делается системой, а не потоком: байты дат и прав
      // не несут, а `capabilities.preservesModified` у локальной ФС объявлен.
      expect(stat.modified, File(source).statSync().modified);
      expect(stat.mode & 0xFFF, File(source).statSync().mode & 0xFFF);
    });

    test('байты идут по ходу дела и в сумме дают размер', () async {
      const size = 32 * 1024 * 1024;
      final source = await makeFile('source.bin', size);
      final target = p.join(root, 'target.bin');

      final chunks = <int>[];
      await copyFileWithProgress(source, target, (bytes) {
        chunks.add(bytes);
        return true;
      });

      expect(chunks, isNotEmpty, reason: 'файл так и остался «нулём до конца»');
      expect(chunks.every((chunk) => chunk > 0), isTrue);
      expect(chunks.fold<int>(0, (sum, chunk) => sum + chunk), size);
    });

    test('маленький файл тоже отчитывается — одним куском', () async {
      final source = await makeFile('source.bin', 64);
      final target = p.join(root, 'target.bin');

      final chunks = <int>[];
      await copyFileWithProgress(source, target, (bytes) {
        chunks.add(bytes);
        return true;
      });

      expect(chunks.fold<int>(0, (sum, chunk) => sum + chunk), 64);
    });

    test('false из колбэка бросает копию', () async {
      // Файл заведомо длиннее одного куска: иначе прерывать нечего.
      const size = 64 * 1024 * 1024;
      final source = await makeFile('source.bin', size);
      final target = p.join(root, 'target.bin');

      var seen = 0;
      await expectLater(
        copyFileWithProgress(source, target, (bytes) {
          seen += bytes;
          return false;
        }),
        throwsA(isA<OperationCanceled>()),
      );

      expect(seen, greaterThan(0));
      expect(seen, lessThan(size), reason: 'копия дошла до конца, а должна была прерваться');
      // Недописанное `copyfile` убирает за собой сам — но полагаться на это
      // движку нельзя: у другого провайдера копия оборвётся иначе, и уборка
      // всё равно его.
      expect(File(target).existsSync(), isFalse);
    });

    test('несуществующий источник даёт FsError, а не падение процесса', () async {
      final target = p.join(root, 'target.bin');

      await expectLater(
        copyFileWithProgress(p.join(root, 'nowhere.bin'), target, (bytes) => true),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
      );
    });
  }, skip: !Platform.isMacOS);
}
