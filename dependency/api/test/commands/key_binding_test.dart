import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Клавиша принадлежит тому, что сейчас на экране.
///
/// Без этого `F5` копировал бы файлы из-под открытого просмотрщика, а ряд
/// кнопок обещал бы то, чего по нажатию не будет.
void main() {
  final f5 = KeyCombination.parse('F5');

  group('экран привязки', () {
    test('по умолчанию — файловые панели', () {
      expect(KeyBinding('F5', 'file.copy').screen, Screens.files);
    });

    test('в своём экране действует', () {
      final binding = KeyBinding('F5', 'file.copy');

      expect(binding.matches(f5, null, screenId: Screens.files), isTrue);
    });

    test('в чужом — нет', () {
      final binding = KeyBinding('F5', 'file.copy');

      expect(binding.matches(f5, null, screenId: 'viewer'), isFalse);
    });

    test('привязка чужого экрана в панелях не срабатывает', () {
      final binding = KeyBinding('F2', 'viewer.wrap', screen: 'viewer');

      expect(binding.matches(KeyCombination.parse('F2'), null, screenId: 'viewer'), isTrue);
      expect(binding.matches(KeyCombination.parse('F2'), null, screenId: Screens.files), isFalse);
    });

    test('привязка «в любом экране» действует везде', () {
      final binding = KeyBinding('F5', 'file.copy', screen: null);

      expect(binding.matches(f5, null, screenId: Screens.files), isTrue);
      expect(binding.matches(f5, null, screenId: 'viewer'), isTrue);
      expect(binding.matches(f5, null), isTrue);
    });

    test('экрана нет вовсе — ограничивать нечем', () {
      // Приложение без интерфейса: тест состояния, сценарий, командная строка.
      expect(KeyBinding('F5', 'file.copy').matches(f5, null), isTrue);
      expect(KeyBinding('F2', 'viewer.wrap', screen: 'viewer').matches(KeyCombination.parse('F2'), null), isTrue);
    });

    test('экран проверяется вместе с остальными условиями, а не вместо них', () {
      final binding = KeyBinding('F5', 'file.copy');

      expect(binding.matches(KeyCombination.parse('F6'), null, screenId: Screens.files), isFalse);
    });
  });
}
