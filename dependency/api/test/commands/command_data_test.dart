import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('поиск по типу', () {
    test('находит значение нужного типа', () {
      final data =
          CommandData()
            ..add('/home')
            ..add(42);

      expect(data.getObject<String>(), '/home');
      expect(data.getObject<int>(), 42);
    });

    test('нет подходящего — null, а не исключение', () {
      expect(CommandData().getObject<String>(), isNull);
    });

    test('из двух значений одного типа берётся последнее', () {
      // Шаг положил свежий путь: дальше по цепочке нужен именно он.
      final data =
          CommandData()
            ..add('/home')
            ..add('/home/docs');

      expect(data.getObject<String>(), '/home/docs');
    });
  });

  group('цепочка данных', () {
    test('своего нет — берётся у родителя', () {
      final parent = CommandData()..add('/home');
      final child = CommandData(parent: parent);

      expect(child.getObject<String>(), '/home');
    });

    test('своё важнее родительского', () {
      final parent = CommandData()..add('/home');
      final child = CommandData(parent: parent)..add('/tmp');

      expect(child.getObject<String>(), '/tmp');
    });

    test('вложенные данные раскрываются', () {
      // Составная команда отдаёт свои данные наружу одним значением.
      final nested = CommandData()..add(7);
      final data = CommandData()..add(nested);

      expect(data.getObject<int>(), 7);
    });
  });

  group('все значения', () {
    test('в порядке добавления, включая родительские', () {
      final parent = CommandData()..add('parent');
      final data =
          CommandData(parent: parent)
            ..add('first')
            ..add('second');

      expect(data.getAllObjects<String>(), ['first', 'second', 'parent']);
    });

    test('чужие типы не попадают', () {
      final data =
          CommandData()
            ..add('текст')
            ..add(1)
            ..add(2);

      expect(data.getAllObjects<int>(), [1, 2]);
    });
  });
}
