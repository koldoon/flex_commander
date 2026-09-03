import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_search/frontend.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Что стоит граница: та же работа через петлю и через порт.
///
/// Ради этого всё и затевалось, и мерить надо **не время работы, а самую
/// долгую паузу цикла событий**: кадр рисуется в том же цикле, и работа, не
/// отдающая его дольше шестнадцати миллисекунд, — это пропущенный кадр
/// (`docs/spec/isolated-core.md`, §2).
///
/// Замер, а не проверка: он ничего не утверждает, а печатает таблицу. Строит
/// он дерево из тысяч файлов и идёт секунды, поэтому ждёт `FC_BENCH=1`.
///
/// Числа сравнимы только внутри одного прогона: машина разогревается по ходу
/// дела. «Петля» и «порт» меряются одной командой, а не разными.
// Замер печатает таблицу — иначе он бесполезен.
// ignore_for_file: avoid_print

void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_bench_border');
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
  /// разрыв между тиками — это ровно то время, когда цикл событий был занят и
  /// не мог ни нарисовать кадр, ни принять нажатие.
  ///
  /// Два прохода: работа, отдающая управление, отдаёт его и измерителю, и его
  /// собственное время попало бы в «всего».
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
    // таймеров — гасить его сразу значило бы не увидеть самой большой паузы.
    await Future<void>.delayed(Duration.zero);
    ticker.cancel();

    return (totalMs: watch.elapsedMicroseconds / 1000, maxStallMs: maxStall.inMicroseconds / 1000);
  }

  /// Поиск по дереву — заявкой, как его заводит окно поиска.
  Future<int> search(AppRuntime runtime, String where) async {
    var found = 0;
    final run = runtime.app.runOperation(
      runId: 'bench#${DateTime.now().microsecondsSinceEpoch}',
      onFound: (batch) => found += batch.length,
    );
    run.start(
      OperationSpec(
        kind: SearchWork.kind,
        targets: Targets.paths([where]),
        options: const {SearchWork.maskOption: '*.txt', SearchWork.recursiveOption: true},
      ),
    );
    await run.result;
    return found;
  }

  test('чего стоит граница: петля против порта', () async {
    if (!enabled) {
      markTestSkipped('замер выключен: FC_BENCH=1 flutter test test/performance/border_bench_test.dart');
      return;
    }

    void row(Object a, Object b, Object c) =>
        print('${a.toString().padRight(28)}${b.toString().padLeft(11)}${c.toString().padLeft(11)}');
    String ms(double value) => value.toStringAsFixed(1);

    final tree = await makeTree(dirs: 60, files: 100);
    final settings = p.join(temp.path, 'settings.json');

    row('работа', 'всего, мс', 'пауза, мс');
    row('-' * 28, '-' * 11, '-' * 11);

    // Петля: ядро в этом же изоляте — так идёт весь остальной прогон.
    final loopback = await initModules(
      backendModules(),
      frontendModules(),
      overrides: AppOverrides(window: FakeWindowService(), store: InMemorySettingsStore()),
    );
    var found = 0;
    final onLoopback = await cost(() async => found = await search(loopback, tree));
    expect(found, 3000, reason: 'замер должен мерить работу, а не её отсутствие');
    row('поиск: петля', ms(onLoopback.totalMs), ms(onLoopback.maxStallMs));
    await loopback.dispose();

    // Порт: то же самое, но ядро в своём изоляте.
    final isolated = await initIsolated(
      frontendModules(),
      overrides: AppOverrides(window: FakeWindowService()),
      settingsPath: settings,
    );
    final onIsolate = await cost(() async => found = await search(isolated, tree));
    expect(found, 3000, reason: 'через порт находки едут пачками — но все');
    row('поиск: порт', ms(onIsolate.totalMs), ms(onIsolate.maxStallMs));
    await isolated.dispose();

    print('');
    print('Пауза — это то, что видит человек: всё, что дольше 16 мс, — пропущенный кадр.');
  });
}
