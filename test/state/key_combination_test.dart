import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('разбор строки', () {
    test('простая клавиша', () {
      final keys = KeyCombination.parse('Enter');
      expect(keys.key, 'Enter');
      expect(keys.ctrl || keys.alt || keys.shift || keys.cmd, isFalse);
    });

    test('модификаторы', () {
      final keys = KeyCombination.parse('Ctrl-Alt-Shift-F5');
      expect(keys.key, 'F5');
      expect(keys.ctrl, isTrue);
      expect(keys.alt, isTrue);
      expect(keys.shift, isTrue);
    });

    test('неизвестный модификатор — ошибка формата', () {
      expect(() => KeyCombination.parse('Hyper-X'), throwsFormatException);
    });

    test('разбор и сборка обратимы', () {
      for (final source in ['Enter', 'Ctrl-R', 'Alt-Shift-Down', 'F10', 'Ctrl-Shift-A']) {
        expect(KeyCombination.parse(source).toString(), source);
      }
    });
  });

  group('клавиша Cmd', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('на macOS это Command', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final keys = KeyCombination.parse('Cmd-O');

      expect(keys.cmd, isTrue);
      expect(keys.ctrl, isFalse);
      expect(keys.toString(), 'Cmd-O');
    });

    test('на других платформах это Ctrl', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final keys = KeyCombination.parse('Cmd-O');

      expect(keys.cmd, isFalse);
      expect(keys.ctrl, isTrue);
      expect(keys.toString(), 'Ctrl-O');
    });
  });

  group('разбор события', () {
    testWidgets('специальные клавиши', (tester) async {
      final combination = KeyCombination.fromEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      );
      expect(combination?.toString(), 'Down');
    });

    testWidgets('буква приводится к верхнему регистру', (tester) async {
      final combination = KeyCombination.fromEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );
      expect(combination?.key, 'A');
    });

    testWidgets('нажатие одного модификатора комбинации не даёт', (tester) async {
      final combination = KeyCombination.fromEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          logicalKey: LogicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(combination, isNull);
    });

    testWidgets('модификаторы берутся из состояния клавиатуры', (tester) async {
      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() => simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft));

      final combination = KeyCombination.fromEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.f5,
          logicalKey: LogicalKeyboardKey.f5,
          timeStamp: Duration.zero,
        ),
      );
      expect(combination?.toString(), 'Shift-F5');
    });
  });
}
