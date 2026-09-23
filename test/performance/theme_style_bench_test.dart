import 'dart:io';

import 'package:flutter/material.dart';

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сколько стоит спросить у темы стиль строки.
///
/// Замер, а не проверка: печатает таблицу и ничего не утверждает. Ждёт
/// `FC_BENCH=1`, как соседи.
// ignore_for_file: avoid_print
void main() {
  final enabled = Platform.environment['FC_BENCH'] == '1';

  test('стиль строки: цена обращения', () async {
    if (!enabled) {
      return;
    }
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    double costOf(String what, TextStyle Function() ask) {
      for (var i = 0; i < 2000; i++) {
        ask();
      }
      const rounds = 200000;
      final spent = Stopwatch()..start();
      for (var i = 0; i < rounds; i++) {
        ask();
      }
      spent.stop();
      return spent.elapsedMicroseconds * 1000 / rounds;
    }

    final row = costOf('rowStyle', () => theme.rowStyle);
    final ui = costOf('uiStyle', () => theme.uiStyle);
    final fixed = costOf('fixedStyle', () => theme.fixedStyle);

    // Список в 925 строк — тот же, на котором мерили перерисовку (А15).
    // Колонок шесть, и каждая спрашивает стиль.
    const rows = 925;
    const columns = 6;
    print('| что | одно обращение | список 925×6 |');
    print('|---|---|---|');
    for (final (name, each) in [('rowStyle', row), ('uiStyle', ui), ('fixedStyle', fixed)]) {
      final build = each * rows * columns / 1000000;
      print('| $name | ${each.toStringAsFixed(0)} нс | ${build.toStringAsFixed(2)} мс |');
    }
  });
}
