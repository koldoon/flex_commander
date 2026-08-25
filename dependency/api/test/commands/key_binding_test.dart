import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

/// Клавиша принадлежит тому, что сейчас показано.
///
/// Без этого `F5` копировал бы файлы из-под открытого просмотрщика, а ряд
/// кнопок обещал бы то, чего по нажатию не будет.
///
/// Именно по **содержимому**, а не по месту: в полноэкранной области бывает и
/// просмотрщик, и редактор, и терминал, а одна клавиша значит в них разное.
class _FakePanel extends ChangeNotifier implements Panel {
  @override
  bool get takesKeyboard => false;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Viewer extends ChangeNotifier implements ViewportState {
  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

void main() {
  final f5 = KeyCombination.parse('F5');
  final f2 = KeyCombination.parse('F2');
  final panel = _FakePanel();
  final viewer = _Viewer();

  group('контекст привязки', () {
    test('по умолчанию — файловые панели', () {
      final binding = KeyBinding('F5', 'file.copy');

      expect(binding.matches(f5, null, content: panel), isTrue);
      expect(binding.matches(f5, null, content: viewer), isFalse);
    });

    test('привязка чужого содержимого в панелях не срабатывает', () {
      final binding = KeyBinding.inState<_Viewer>('F2', 'viewer.wrap');

      expect(binding.matches(f2, null, content: viewer), isTrue);
      expect(binding.matches(f2, null, content: panel), isFalse);
    });

    test('привязка «везде» действует при любом содержимом', () {
      final binding = KeyBinding.anywhere('F5', 'file.copy');

      expect(binding.matches(f5, null, content: panel), isTrue);
      expect(binding.matches(f5, null, content: viewer), isTrue);
      expect(binding.matches(f5, null), isTrue);
    });

    test('области нет вовсе — ограничивать нечем', () {
      // Приложение без интерфейса: тест состояния, сценарий, командная строка.
      expect(KeyBinding('F5', 'file.copy').matches(f5, null), isTrue);
      expect(KeyBinding.inState<_Viewer>('F2', 'viewer.wrap').matches(f2, null), isTrue);
    });

    test('содержимое проверяется вместе с остальными условиями, а не вместо них', () {
      final binding = KeyBinding('F5', 'file.copy');

      expect(binding.matches(KeyCombination.parse('F6'), null, content: panel), isFalse);
    });
  });
}
