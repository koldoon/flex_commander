import 'dart:convert';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Клавиатура в полноэкранном терминале: что именно уезжает программе.
///
/// Проверяется байтами, а не «работает ли»: терминал говорит с программой
/// управляющими последовательностями, и `Backspace`, не доехавший до неё, со
/// стороны выглядит как «клавиша не нажимается».
void main() {
  late AppRuntime runtime;
  late FakePty pty;

  Future<void> openTerminal(WidgetTester tester) async {
    pty = FakePty();
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')], null, pty)..home = '/home',
      modules: modulesWithTerminal(),
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();

    // Экран показывается только после того, как оболочка ответила на уговор:
    // до этого на нём видна его же строка.
    AgreeingShell(pty.session).greet();
    await tester.pumpAndSettle();
    pty.session.writes.clear();
  }

  List<int> sent() => [for (final chunk in pty.session.writes) ...utf8.encode(chunk)];

  /// Тело теста идёт на macOS: там `Cmd` и `Ctrl` — разные клавиши, а на
  /// подставной платформе теста `Cmd-O` («открыть в системе») превращается в
  /// тот же `Ctrl-O`, что и наш терминал.
  Future<void> onMacOs(WidgetTester tester, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      await tester.pump(const Duration(milliseconds: 20));
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('Backspace доезжает до программы', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      // `\x7f`, как у xterm: именно его ждёт оболочка.
      expect(sent(), [0x7f]);
    });
  });

  testWidgets('печатное берётся из символа раскладки, а не из клавиши', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      // Русская раскладка на macOS: клавиша та же (физическая `A`), символ
      // другой. Разбирать нажатие по клавише значило бы печатать `a` вместо
      // `ф` — или не печатать вовсе.
      await simulateKeyDownEvent(LogicalKeyboardKey.keyA, character: 'ф');
      await tester.pumpAndSettle();

      expect(utf8.decode(sent()), 'ф');
    });
  });

  testWidgets('латиница доезжает так же', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      await simulateKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pumpAndSettle();

      expect(utf8.decode(sent()), 'a');
    });
  });

  testWidgets('служебные клавиши уходят последовательностями', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent(), [0x0d]);

      pty.session.writes.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(sent(), [0x1b, 0x5b, 0x41], reason: 'ESC [ A — стрелка вверх');

      // `Tab` внутри терминала принадлежит программе, а не переключению
      // панелей: там он дополняет.
      pty.session.writes.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(sent(), [0x09]);
    });
  });

  testWidgets('Esc уходит программе с первого нажатия', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      // Внутри терминала `Esc` принадлежит программе: у неё он и меню, и
      // отмена. Приложение его себе не забирает.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(sent(), [0x1b]);

      pty.session.writes.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(sent(), [0x1b], reason: 'и со второго — тот же байт');
    });
  });

  testWidgets('в прикладном режиме стрелка уходит как ESC O A', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      // Так просят `mc`, `vim` и `less`: `ESC [ ? 1 h` — и стрелки переходят в
      // прикладной режим. Именно `ESC O A` стоит у них в описании терминала, и
      // по обычному `ESC [ A` они стрелку не узнают — в `mc` курсор просто не
      // двигается.
      pty.session.emit('\x1b[?1h');
      await tester.pumpAndSettle();
      pty.session.writes.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(sent(), [0x1b, 0x4f, 0x41], reason: 'ESC O A');

      // Выключили — снова обычная.
      pty.session.emit('\x1b[?1l');
      await tester.pumpAndSettle();
      pty.session.writes.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(sent(), [0x1b, 0x5b, 0x41], reason: 'ESC [ A');
    });
  });

  testWidgets('Ctrl-C прерывает то, что внутри', (tester) async {
    await onMacOs(tester, () async {
      await openTerminal(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(sent(), [0x03]);
    });
  });
}
