import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Сколько стоит прочитать каталог — по способам чтения.
///
/// Замер, а не проверка: он ничего не утверждает, а печатает таблицу. Включать
/// его в каждый прогон незачем — он строит десятки тысяч файлов и идёт
/// секунды, — поэтому он ждёт `FC_BENCH=1`, как живой тест 7-Zip ждёт саму
/// программу.
///
/// Рядом стоит обычная проверка: способы обязаны давать **одинаковый**
/// результат. Ускорение, потерявшее половину записей, — не ускорение.
///
/// Числа сравнивать можно только внутри одного прогона и в одинаковых
/// условиях: виртуальная машина разогревается по ходу дела, и та же
/// сортировка в конце прогона идёт втрое быстрее, чем в начале. Поэтому «до»
/// и «после» меряются одной и той же командой, а не разными.
// Замер печатает таблицу — иначе он бесполезен.
// ignore_for_file: avoid_print

void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_bench');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<String> makeDirectory(int count) async {
    final path = p.join(temp.path, 'dir_$count');
    await Directory(path).create(recursive: true);
    for (var i = 0; i < count; i++) {
      // Имена разной длины и с числами — сортировке потом будет что делать.
      await File(p.join(path, 'file_${i.toString().padLeft(5, '0')}.txt')).writeAsString('$i');
    }
    return path;
  }

  /// Среднее время одного чтения, миллисекунды.
  Future<double> measure(Future<void> Function() body, {int runs = 5}) async {
    // Прогрев: первый заход платит за прогрев кэшей файловой системы.
    await body();

    final watch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await body();
    }
    watch.stop();
    return watch.elapsedMicroseconds / runs / 1000;
  }

  test('чтение в изоляте и на месте дают одинаковый результат', () async {
    // Изолят — это только «где», а не «что»: расходиться им нельзя.
    final path = await makeDirectory(200);
    await Link(p.join(path, 'link')).create(p.join(path, 'file_00000.txt'));

    final inIsolate = await readDirectory(path);
    final blocking = readDirectoryBlocking(path);

    expect(blocking, hasLength(inIsolate.length));

    final byName = {for (final entry in blocking) entry.name: entry};
    for (final entry in inIsolate) {
      final other = byName[entry.name];
      expect(other, isNotNull, reason: 'потеряна запись ${entry.name}');
      expect(other!.fileType, entry.fileType, reason: entry.name);
      expect(other.size, entry.size, reason: entry.name);
      expect(other.modeString, entry.modeString, reason: entry.name);
      expect(other.linkTarget, entry.linkTarget, reason: entry.name);
      expect(other.modified, entry.modified, reason: entry.name);
    }
  });

  test('сколько стоит открыть каталог целиком', () async {
    if (!enabled) {
      markTestSkipped('замер выключен');
      return;
    }

    void row(Object a, Object b) => print('${a.toString().padRight(10)}${b.toString().padLeft(14)}');

    // То же, что делает панель по Enter: чтение в изоляте плюс постройка узлов
    // уже в главном — узлы держат ссылки на провайдера и на родителя, а такие
    // связи через границу изолята не переносят.
    final provider = LocalTreeProvider();
    row('записей', 'открытие');

    for (final count in [1000, 10000]) {
      final path = await makeDirectory(count);
      final dir = (await provider.resolvePath().run(path))! as DirectoryNode;

      final listing = await measure(() => provider.getDirectoryListing().run(ListingParams(dir)));
      row(count, listing.toStringAsFixed(2));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('сколько стоит отсортировать каталог', () async {
    if (!enabled) {
      markTestSkipped('замер выключен');
      return;
    }

    void row(Object a, Object b) => print('${a.toString().padRight(10)}${b.toString().padLeft(12)}');

    final provider = LocalTreeProvider(readInIsolate: false);
    row('записей', 'сортировка');

    for (final count in [1000, 10000]) {
      // Имена как в жизни: разный регистр и числа внутри — «естественный»
      // порядок именно на них и работает.
      final nodes = <FsNode>[
        for (var i = 0; i < count; i++)
          FileNode(provider: provider, name: '${i.isEven ? 'Файл' : 'file'}_${count - i}_v${i % 17}.txt'),
      ];

      const spec = SortSpec();
      final watch = Stopwatch()..start();
      const runs = 5;
      for (var i = 0; i < runs; i++) {
        nodes.toList().sort(comparatorFor(spec));
      }
      watch.stop();

      row(count, (watch.elapsedMicroseconds / runs / 1000).toStringAsFixed(2));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('сколько стоит прочитать каталог', () async {
    if (!enabled) {
      markTestSkipped('замер выключен: FC_BENCH=1 flutter test test/performance/listing_bench_test.dart');
      return;
    }

    void row(Object a, Object b, Object c, Object d) => print(
      '${a.toString().padRight(10)}${b.toString().padLeft(12)}${c.toString().padLeft(14)}${d.toString().padLeft(14)}',
    );

    String ms(double value) => value.toStringAsFixed(2);

    row('записей', 'в изоляте', 'на месте', 'цена изолята');
    for (final count in [100, 1000, 10000]) {
      final path = await makeDirectory(count);

      final inIsolate = await measure(() => readDirectory(path));
      final blocking = await measure(() async => readDirectoryBlocking(path));

      row(count, ms(inIsolate), ms(blocking), ms(inIsolate - blocking));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
