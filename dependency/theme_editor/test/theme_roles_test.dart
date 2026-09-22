import 'dart:io';

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Роль контракта: имя и группа, в которой она объявлена.
typedef Declared = ({String name, String group});

/// Что объявлено в контракте оформления.
///
/// Чтением исходника, а не отражением: `dart:mirrors` во Flutter не работает, и
/// другого способа сосчитать геттеры в Dart нет. Каталог, молча разошедшийся с
/// контрактом, означал бы роль, которую в приложении не поправить и о которой
/// никто не узнает (`docs/spec/theme-editor.md`, §7).
///
/// Путь относительный — и это единственная слабость приёма: переедет пакет,
/// тест это скажет, а не промолчит.
List<Declared> declared(String contract, String type) {
  final file = File('../ui_api/lib/src/theme/$contract');
  expect(file.existsSync(), isTrue, reason: 'контракт переехал: ${file.path}');

  final group = RegExp(r'^\s*// --- (.+?) ---');
  final role = RegExp('^\\s*$type get (\\w+)\\s*(;|=>)');

  var current = '';
  final roles = <Declared>[];
  for (final line in file.readAsLinesSync()) {
    if (group.firstMatch(line) case final match?) {
      current = match.group(1)!;
      continue;
    }
    if (role.firstMatch(line) case final match?) {
      roles.add((name: match.group(1)!, group: current));
    }
  }
  return roles;
}

void main() {
  group('каталог сверен с контрактом', () {
    test('цвета: те же роли и те же группы', () {
      final contract = declared('app_colors.dart', 'Color');
      // Цветов ANSI здесь нет: в контракте они списком (`List<Color>`), а в
      // каталоге — шестнадцатью ролями, и сверяются отдельным тестом ниже.
      expect(contract.length, 56, reason: 'роли добавили или убрали — поправьте и накладку, и каталог');

      final catalog = {for (final role in colorRoles) role.name: role.section};
      for (final role in contract) {
        expect(catalog, contains(role.name), reason: 'роль ${role.name} есть в контракте, а править её нечем');
        expect(
          catalog[role.name],
          colorSections[role.group],
          reason: 'роль ${role.name} объявлена в группе «${role.group}», а стоит в другом разделе',
        );
      }
    });

    test('размеры: те же роли, те же группы и род у каждой', () {
      final contract = declared('app_metrics.dart', 'double');
      expect(contract.length, 94);

      final catalog = {for (final role in metricRoles) role.name: role};
      for (final role in contract) {
        expect(catalog, contains(role.name), reason: 'размер ${role.name} есть в контракте, а править его нечем');
        expect(
          catalog[role.name]!.section,
          metricSections[role.group],
          reason: 'размер ${role.name} не в своём разделе',
        );
      }
    });

    test('лишнего в каталоге нет: роль, которой в контракте не стало, ушла бы в никуда', () {
      final colors = {for (final role in declared('app_colors.dart', 'Color')) role.name};
      final ansi = {for (var index = 0; index < 16; index++) OverlayColors.ansiRole(index)};

      expect(colorRoles.map((role) => role.name).toSet().difference(colors).difference(ansi), isEmpty);
      expect(
        metricRoles.map((role) => role.name).toSet().difference({
          for (final role in declared('app_metrics.dart', 'double')) role.name,
        }),
        isEmpty,
      );
    });

    test('шрифты: три роли, и накладка знает все три', () {
      // Шрифты сверять по исходнику незачем: их три, и каждая правится своим
      // полем — компилятор их и считает ([OverlayFonts]).
      const base = DefaultFonts();
      const overlay = OverlayFonts(base, uiFont: 'Inter', fixedFont: 'Menlo', fallback: ['Courier']);

      expect(overlay.ui, 'Inter');
      expect(overlay.fixed, 'Menlo');
      expect(overlay.fixedFallback, ['Courier']);
    });

    test('каждая роль читается у темы: замыкание ведёт туда, куда названо', () {
      const colors = DefaultColors();
      const metrics = DefaultMetrics();

      // Смысл не в значениях, а в том, что ни одно замыкание не падает и не
      // ведёт в соседнюю роль: `iconColumnWidth` считается из трёх других.
      expect(colorRoles.map((role) => role.read(colors)), everyElement(isA<Color>()));
      expect(metricRoles.map((role) => role.read(metrics)), everyElement(isA<double>()));
      expect(colorRoles.firstWhere((role) => role.name == 'windowBackground').read(colors), colors.windowBackground);
      expect(metricRoles.firstWhere((role) => role.name == 'rowHeight').read(metrics), metrics.rowHeight);
    });

    test('пределы метрики берутся у рода, а не у роли', () {
      final rowHeight = metricRoles.firstWhere((role) => role.name == 'rowHeight');
      final factor = metricRoles.firstWhere((role) => role.name == 'dialogWidthFactor');

      expect(rowHeight.kind, MetricKind.size);
      // Верх размера выше самой большой меры темы: иначе умолчание нельзя было
      // бы набрать обратно.
      expect(rowHeight.kind.max, greaterThanOrEqualTo(const DefaultMetrics().dialogMaxWidth));
      // У доли нуля нет: окно нулевой ширины не разглядеть.
      expect(factor.kind, MetricKind.fraction);
      expect(factor.kind.min, greaterThan(0));
    });

    test('умолчания темы укладываются в пределы своего рода', () {
      const metrics = DefaultMetrics();
      for (final role in metricRoles) {
        final value = role.read(metrics);
        expect(
          value,
          inInclusiveRange(role.kind.min, role.kind.max),
          reason: 'умолчание ${role.name} = $value не влезает в род ${role.kind.name}',
        );
      }
    });
  });

  group('накладка', () {
    test('своё там, где задано, чужое во всём остальном', () {
      const base = DefaultColors();
      final overlay = OverlayColors(base, {'cursorBackground': const Color(0xFF2D6CDF)});

      expect(overlay.cursorBackground, const Color(0xFF2D6CDF));
      expect(overlay.windowBackground, base.windowBackground);
    });

    test('цвет ANSI правится по номеру, соседние остаются как в теме', () {
      const base = DefaultColors();
      final overlay = OverlayColors(base, {OverlayColors.ansiRole(4): const Color(0xFF2D6CDF)});

      expect(overlay.terminalAnsi[4], const Color(0xFF2D6CDF));
      expect(overlay.terminalAnsi[5], base.terminalAnsi[5]);
      expect(overlay.terminalAnsi, hasLength(base.terminalAnsi.length));
    });

    test('размеры — тем же способом', () {
      const base = DefaultMetrics();
      const overlay = OverlayMetrics(base, {'rowHeight': 26});

      expect(overlay.rowHeight, 26);
      expect(overlay.rowGap, base.rowGap);
    });

    test('пустая накладка — это сама тема', () {
      const base = DefaultColors();
      final overlay = OverlayColors(base, const {});

      for (final role in colorRoles) {
        expect(role.read(overlay), role.read(base), reason: 'роль ${role.name} подменилась без правки');
      }
    });
  });
}
