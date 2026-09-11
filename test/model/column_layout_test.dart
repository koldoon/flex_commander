import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Объявленные колонки — те же, что приносит модуль панелей.
List<ColumnSpec> get _declared => FsColumnSpecs.all;

ColumnLayout _saved(List<Map<String, Object?>> items) => ColumnLayout.fromJson(items);

void main() {
  group('раскладка хранит выбор, а не геометрию', () {
    test('пустая раскладка означает «как объявлено»', () {
      final shown = ColumnLayout.empty.resolvedWith(_declared);

      // Все колонки таблицы в порядке объявления. Ветвь дерева в раскладку
      // панели не входит: её ставит себе свой вид.
      expect(shown.columns.map((c) => c.id), [
        'icon',
        'name',
        'path',
        'ext',
        'size',
        'modified',
        'created',
        'accessed',
        'attributes',
      ]);
      expect(shown.find('size')?.width, 64);
      expect(shown.find('size')?.title, 'Size');
      expect(shown.find('path')?.visible, isFalse);
    });

    test('порядок и видимость берутся из раскладки', () {
      final shown = _saved([
        {'id': 'icon', 'visible': true},
        {'id': 'name', 'visible': true},
        {'id': 'modified', 'visible': true},
        {'id': 'ext', 'visible': false},
      ]).resolvedWith(_declared);

      expect(shown.columns.take(4).map((c) => c.id), ['icon', 'name', 'modified', 'ext']);
      expect(shown.find('ext')?.visible, isFalse);
      // Чего в файле не было — следом, в порядке объявления.
      expect(shown.columns.map((c) => c.id), containsAll(['size', 'created', 'attributes']));
    });

    test('ширина берётся из раскладки, только если её правил человек', () {
      final shown = _saved([
        {'id': 'modified', 'width': 90, 'visible': true},
        {'id': 'size', 'visible': true},
      ]).resolvedWith(_declared);

      expect(shown.find('modified')?.width, 90);
      // Ширины в файле нет — значит объявленная. Так правка оформления
      // доходит до того, у кого настройки давно есть.
      expect(shown.find('size')?.width, 64);
    });

    test('ширина закреплённой колонки из раскладки не берётся никогда', () {
      final shown = _saved([
        {'id': 'icon', 'width': 999, 'visible': true},
      ]).resolvedWith(_declared);

      expect(shown.find('icon')?.width, 28);
    });

    test('закреплённую колонку нельзя спрятать через файл настроек', () {
      final shown = _saved([
        {'id': 'name', 'visible': false},
      ]).resolvedWith(_declared);

      expect(shown.find('name')?.visible, isTrue);
    });

    test('в файл уходит только правленая ширина', () {
      final layout = ColumnLayout.empty.resolvedWith(_declared);

      expect(layout.toJson().every((item) => !item.containsKey('width')), isTrue);
      expect(layout.resize('size', 120).toJson().firstWhere((item) => item['id'] == 'size')['width'], 120);
    });

    test('не список даёт пустую раскладку', () {
      expect(ColumnLayout.fromJson('нет').columns, isEmpty);
    });
  });

  group('незнакомая колонка спит', () {
    test('её не рисуют', () {
      final shown = _saved([
        {'id': 'rating', 'width': 50, 'visible': true},
        {'id': 'name', 'visible': true},
      ]).resolvedWith(_declared);

      expect(shown.find('rating'), isNull);
      expect(shown.columns.first.id, 'name');
    });

    test('но она переживает запись', () {
      // Выключили модуль на один запуск — колонка обязана вернуться на место,
      // когда его включат обратно (`docs/spec/column-registry.md`, §4.2).
      final saved = _saved([
        {'id': 'name', 'visible': true},
        {'id': 'rating', 'width': 50, 'visible': true},
      ]);
      final shown = saved.resolvedWith(_declared);
      final merged = saved.merge(shown);

      expect(merged.find('rating')?.visible, isTrue);
      expect(merged.find('rating')?.width, 50);
      expect(ColumnLayout.fromJson(merged.toJson()).find('rating')?.width, 50);
    });

    test('и переживает перестановку соседей', () {
      final saved = _saved([
        {'id': 'name', 'visible': true},
        {'id': 'rating', 'visible': true},
        {'id': 'size', 'visible': true},
      ]);
      final shown = saved.resolvedWith(_declared);
      final moved = shown.moveColumn(shown.indexOf('size'), 1);

      expect(saved.merge(moved).find('rating'), isNotNull);
    });
  });

  group('просьба источника', () {
    test('колонка источника видима поверх раскладки', () {
      final shown = ColumnLayout.empty.resolvedWith(_declared, extra: {'path'});

      expect(shown.find('path')?.visible, isTrue);
    });

    test('и в раскладку не попадает', () {
      // Уйдя из находок, человек видит те колонки, что настраивал.
      final saved = ColumnLayout.empty;
      expect(saved.find('path'), isNull);
    });
  });

  group('перестановка колонок', () {
    late ColumnLayout layout;

    setUp(() => layout = ColumnLayout.empty.resolvedWith(_declared));

    test('колонка встаёт на указанную позицию', () {
      final moved = layout.moveColumn(layout.indexOf('modified'), 2);

      expect(moved.columns.map((c) => c.id).take(5), ['icon', 'name', 'modified', 'path', 'ext']);
    });

    test('закреплённые колонки не двигаются', () {
      final moved = layout.moveColumn(layout.indexOf('name'), 4);

      expect(moved.columns.map((c) => c.id), layout.columns.map((c) => c.id));
    });

    test('другие колонки не встают перед закреплёнными', () {
      final moved = layout.moveColumn(layout.indexOf('size'), 0);

      expect(moved.columns.map((c) => c.id).take(3), ['icon', 'name', 'size']);
      expect(layout.firstMovableIndex, 2);
    });

    test('порядок переживает сохранение', () {
      final moved = layout.moveColumn(layout.indexOf('modified'), 2);
      final restored = ColumnLayout.fromJson(moved.toJson()).resolvedWith(_declared);

      expect(restored.columns.map((c) => c.id), moved.columns.map((c) => c.id));
    });
  });
}
