import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/core/settings_hub.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сколько стоит вопрос «есть ли что записывать» — тот, который панель задаёт
/// на каждое своё сообщение.
///
/// Замер, а не проверка: печатает таблицу и ничего не утверждает. Ждёт
/// `FC_BENCH=1`, как соседи.
// ignore_for_file: avoid_print
void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  /// Настройки как у живого человека: две стороны, в каждой по паре сессий с
  /// историей и раскрытыми ветвями.
  PanelSettings session(String path, {int steps = 20, int expanded = 30}) => PanelSettings(
    path: path,
    cursor: 'file-7.txt',
    cursorPath: '$path/file-7.txt',
    history: [for (var i = 0; i < steps; i++) PathStep(path: '$path/step-$i', cursor: 'file-$i.txt')],
    expanded: [for (var i = 0; i < expanded; i++) '$path/branch-$i'],
  );

  /// Один замер: сколько стоит вопрос при таких настройках.
  double costOf(Map<PanelId, PanelSettings> sessions) {
    final hub = SettingsHub(
      store: SettingsStore(filePath: '${Directory.systemTemp.path}/fc_bench_settings.json'),
      stored: AppSettings(),
      panelSettings: (panel) => sessions[panel],
    );
    addTearDown(hub.dispose);

    // Разогрев: виртуальная машина в начале прогона медленнее.
    for (var i = 0; i < 200; i++) {
      hub.panelsChanged();
    }

    const rounds = 1000;
    final spent = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      hub.panelsChanged();
    }
    spent.stop();
    return spent.elapsedMicroseconds / rounds;
  }

  test('вопрос «есть ли что записывать» — цена одного шага курсора', () async {
    if (!enabled) {
      return;
    }
    final plain = costOf({
      PanelId.left: session('/Users/koldoon/Developer'),
      PanelId.right: session('/Users/koldoon/Downloads'),
    });
    // Дерево, раскрытое как на живом замере А15: 1382 ветви.
    final tree = costOf({
      PanelId.left: session('/Users/koldoon/Developer', expanded: 1382),
      PanelId.right: session('/Users/koldoon/Downloads'),
    });

    print('| что | на шаг курсора | сто шагов |');
    print('|---|---|---|');
    print('| обычные панели | ${plain.toStringAsFixed(1)} мкс | ${(plain / 10).toStringAsFixed(1)} мс |');
    print('| дерево на 1382 ветви | ${tree.toStringAsFixed(1)} мкс | ${(tree / 10).toStringAsFixed(1)} мс |');
  });

}
