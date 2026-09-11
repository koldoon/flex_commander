import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Объявления штатных колонок.
///
/// Спецификация — `docs/spec/column-registry.md`.
void main() {
  test('колонка значка вмещает отступ, глиф и просвет до имени', () {
    // Ширина колонки объявляется модулем, а метрик он не видит: настоящую
    // ширину считает `FileIconSize.columnWidth` по теме. Согласованность
    // объявления с оформлением проверяется здесь.
    const metrics = DefaultMetrics();
    expect(FsColumnSpecs.icon.width, closeTo(metrics.iconColumnWidth, 1));
    expect(FsColumnSpecs.icon.minWidth, FsColumnSpecs.icon.width);
  });

  test('резиновая колонка одна — имя', () {
    expect(FsColumnSpecs.all.where((column) => column.flexible && column.inLayout).map((c) => c.id), ['name']);
  });

  test('несортируема только колонка значка', () {
    expect(FsColumnSpecs.all.where((column) => !column.sortable).map((c) => c.id), ['icon']);
  });

  test('заголовок есть у всех, кроме значка', () {
    expect(FsColumnSpecs.all.where((column) => column.title.isEmpty).map((c) => c.id), ['icon']);
  });

  test('ветвь дерева в раскладку панели не входит', () {
    expect(FsColumnSpecs.all.where((column) => !column.inLayout).map((c) => c.id), ['tree']);
  });
}
