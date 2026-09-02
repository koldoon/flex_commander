import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Чем тяжёлая работа обходится интерфейсу.
///
/// Замер, а не проверка: он ничего не утверждает, а печатает таблицу. Ждёт
/// `FC_BENCH=1` — как и соседний замер чтения каталога, и по той же причине: он
/// строит тысячи файлов и идёт секундами.
///
/// **Мера здесь — не время работы, а самая долгая пауза цикла событий.** Время
/// говорит, сколько ждать; пауза говорит, что в это время видит человек. Кадр
/// рисуется в том же цикле, и работа, не отдающая его дольше шестнадцати
/// миллисекунд, — это пропущенный кадр; дольше сотни — «приложение не
/// отвечает».
///
/// Числа сравнимы только внутри одного прогона: машина разогревается по ходу
/// дела. «До» и «после» меряются одной командой, а не разными.
// Замер печатает таблицу — иначе он бесполезен.
// ignore_for_file: avoid_print

void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_bench_heavy');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Дерево на диске: [dirs] каталогов по [files] файлов в каждом.
  Future<String> makeTree({required int dirs, required int files}) async {
    final root = p.join(temp.path, 'tree');
    for (var d = 0; d < dirs; d++) {
      // В два уровня: обход должен ходить вглубь, а не по одному каталогу.
      final path = p.join(root, 'pack_${d ~/ 10}', 'dir_$d');
      await Directory(path).create(recursive: true);
      for (var f = 0; f < files; f++) {
        await File(p.join(path, 'file_$f.${f.isEven ? 'txt' : 'dat'}')).writeAsString('$d/$f');
      }
    }
    return root;
  }

  /// Что стоила работа: сколько шла и на сколько дольше всего замолкала.
  ///
  /// Паузу меряет обычный таймер: он **должен** тикать каждую миллисекунду, и
  /// разрыв между тиками — это ровно то время, когда цикл событий был занят
  /// работой и не мог ни нарисовать кадр, ни принять нажатие.
  ///
  /// **Два прохода, и это не лень, а необходимость.** Работа, отдающая
  /// управление, отдаёт его и самому измерителю: тикающий таймер получает своё
  /// ровно во вдохи, и его собственное время попадает в «всего». Поэтому время
  /// меряется проходом без измерителя, а пауза — проходом с ним.
  Future<({double totalMs, double maxStallMs})> cost(Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    watch.stop();

    final sinceTick = Stopwatch()..start();
    var maxStall = Duration.zero;
    final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (sinceTick.elapsed > maxStall) {
        maxStall = sinceTick.elapsed;
      }
      sinceTick
        ..reset()
        ..start();
    });

    await body();

    // Оборот очереди **до** остановки таймера: после синхронной работы
    // продолжение приходит микрозадачей, а микрозадачи выполняются раньше
    // таймеров — гасить его сразу значило бы не увидеть самой большой паузы,
    // той, что работа только что и устроила.
    await Future<void>.delayed(Duration.zero);
    ticker.cancel();

    return (totalMs: watch.elapsedMicroseconds / 1000, maxStallMs: maxStall.inMicroseconds / 1000);
  }

  test('чем тяжёлая работа обходится интерфейсу', () async {
    if (!enabled) {
      markTestSkipped('замер выключен: FC_BENCH=1 flutter test test/performance/heavy_work_bench_test.dart');
      return;
    }

    void row(Object a, Object b, Object c) =>
        print('${a.toString().padRight(28)}${b.toString().padLeft(12)}${c.toString().padLeft(16)}');

    String ms(double value) => value.toStringAsFixed(1);

    row('работа', 'всего, мс', 'пауза, мс');

    // --- обход дерева поиском ---
    //
    // То, с чего всё началось: `*.txt` по дереву. Каталоги читаются синхронно
    // и в этом же изоляте.
    final treePath = await makeTree(dirs: 200, files: 30);
    final local = LocalTreeProvider();
    final root = (await local.resolvePath().run(treePath))! as DirectoryNode;

    var found = 0;
    final walk = await cost(() async {
      final run = SearchRun.from(root, onFound: (_) => found++);
      run.start(const SearchQuery(mask: '*.txt'));
      await run.result;
    });
    row('поиск: обход + узлы', ms(walk.totalMs), ms(walk.maxStallMs));
    // Дважды: замер делает два прохода — время и паузу порознь.
    expect(found, 6000, reason: 'замер должен мерить работу, а не её отсутствие');

    // Тот же код **без вдоха** — как было до правки. Сравнивать вдох с его
    // отсутствием надо на одном и том же коде, иначе в разницу попадёт всё
    // остальное.
    SearchRun.breath = const Duration(days: 1);
    final noBreath = await cost(() async {
      final run = SearchRun.from(root, onFound: (_) {});
      run.start(const SearchQuery(mask: '*.txt'));
      await run.result;
    });
    SearchRun.breath = const Duration(milliseconds: 8);
    row('он же, без вдоха', ms(noBreath.totalMs), ms(noBreath.maxStallMs));

    // Обход **без сборки узлов**: только пути и маска. Разница с первой строкой
    // и есть цена узлов — а узлы через границу изолята не переносятся, их в
    // любом случае собирает эта сторона.
    final paths = await cost(() async => _walkBlocking(treePath, '*.txt'));
    row('обход без узлов, здесь', ms(paths.totalMs), ms(paths.maxStallMs));

    // Он же в изоляте — набросок того, к чему идём: наружу приходит только
    // совпавшее, и узлы собираются лишь для него.
    final inIsolate = await cost(() async => Isolate.run(() => _walkBlocking(treePath, '*.txt')));
    row('обход без узлов, в изоляте', ms(inIsolate.totalMs), ms(inIsolate.maxStallMs));

    // --- распаковка из архива ---
    //
    // `inflate` идёт в этом же изоляте (`zip_tree_provider.dart`), и на большом
    // файле это та же болезнь, что была у обхода.
    final big = File(p.join(temp.path, 'big.txt'));
    // Текст, а не случайные байты: случайные не сжимаются, и распаковывать было
    // бы нечего.
    await big.writeAsString('строка, которая неплохо сжимается, и её номер: ' * 200000);

    final archivePath = p.join(temp.path, 'big.zip');
    await encodeZipArchive(
      archivePath: archivePath,
      entries: [ZipItem.file('big.txt', big.path)],
      level: 6,
      op: TaskOperation<Object?, void>((op, _) async {}),
    );

    final host = (await local.resolvePath().run(archivePath))!;
    final zip =
        await ZipTreeProvider.open(host, staging: const LocalStagingArea(), credentials: FakeCredentials())
            as ZipTreeProvider;
    final inside = (await zip.resolvePath().run('/big.txt'))!;

    final unpack = await cost(() async {
      var bytes = 0;
      await for (final chunk in await zip.openRead(inside)) {
        bytes += chunk.length;
      }
      expect(bytes, await big.length(), reason: 'распаковали не всё — мерить нечего');
    });
    final megabytes = (await big.length()) / 1024 / 1024;
    row('распаковка ${megabytes.toStringAsFixed(1)} МБ из zip', ms(unpack.totalMs), ms(unpack.maxStallMs));

    await zip.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Обход дерева синхронными вызовами — как его делает провайдер локальной ФС.
///
/// Набросок для замера, а не реализация: наружу отдаётся число совпавшего.
/// Узлы через границу изолята не переносятся — их собирает та сторона, которой
/// они принадлежат.
int _walkBlocking(String root, String mask) {
  final pattern = FileMask.parse(mask);
  final queue = <String>[root];
  var found = 0;

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    final List<FileSystemEntity> listing;
    try {
      listing = Directory(path).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in listing) {
      final name = p.basename(entity.path);
      if (pattern.matches(name)) {
        found++;
      }
      if (entity is Directory) {
        queue.add(entity.path);
      }
    }
  }
  return found;
}
