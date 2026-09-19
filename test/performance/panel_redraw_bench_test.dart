import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Во что обходится одно нажатие стрелки (`docs/spec/panel-redraw.md`).
///
/// Замер, а не проверка: он ничего не утверждает, а печатает таблицу — кого и
/// сколько раз каркас пересобрал. Сторож с порогом живёт отдельно
/// (`dependency/panels/test/redraw_test.dart`); здесь видно, **из чего**
/// складывается число.
///
/// Ждёт `FC_BENCH=1`, как и соседние замеры: поднимать ради него приложение на
/// каждом прогоне незачем.
///
/// Числа сравнимы только внутри одного прогона: машина разогревается по ходу
/// дела.
// Замер печатает таблицу — иначе он бесполезен.
// ignore_for_file: avoid_print

void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  testWidgets('нажатие стрелки: кого пересобирает', (tester) async {
    if (!enabled) {
      return;
    }

    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 2000; i++) FakeEntry.file('/home/file-${i.toString().padLeft(4, '0')}.txt', size: 100 + i),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    final AppRuntime runtime = await testApp(provider: provider, modules: featureModules(), settings: settings);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();

    final counts = <String, int>{};
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null || !(message.startsWith('Rebuilding ') || message.startsWith('Building '))) {
        return;
      }
      final name = message.split(' ').skip(1).join(' ').split(RegExp('[-(]')).first.trim();
      counts[name] = (counts[name] ?? 0) + 1;
    };

    final watch = Stopwatch()..start();
    debugPrintRebuildDirtyWidgets = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    debugPrintRebuildDirtyWidgets = false;
    watch.stop();
    debugPrint = original;

    final rows = tester.widgetList(find.byType(FileTableRow)).length;
    final total = counts.values.fold(0, (sum, count) => sum + count);
    print('--- одно нажатие: $total пересборок, ${watch.elapsedMilliseconds} мс, строк на экране $rows ---');
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.take(20)) {
      print('${entry.value.toString().padLeft(5)}  ${entry.key}');
    }

    await disposeScreen(tester);
  });
}
