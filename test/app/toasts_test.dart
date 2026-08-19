import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/toast_controller.dart';
import 'package:flex_commander/view/function_bar/function_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Всплывающие сообщения: служба и то, что от неё видно на экране.
void main() {
  group('служба', () {
    test('два одинаковых сообщения подряд — это два показа', () {
      final toasts = ToastController();
      addTearDown(toasts.dispose);

      toasts.show('Show hidden files: On');
      final first = toasts.current!.id;
      toasts.show('Show hidden files: On');

      // По тексту их не различить, а моргнуть второе должно: иначе повторное
      // переключение выглядит как несработавшее.
      expect(toasts.current!.id, isNot(first));
    });

    test('о каждом показе сообщается наружу', () {
      final toasts = ToastController();
      addTearDown(toasts.dispose);

      var notified = 0;
      toasts.addListener(() => notified++);

      toasts
        ..show('раз')
        ..hide()
        // Прятать нечего — уведомлять не о чем.
        ..hide();

      expect(notified, 2);
    });

    // Время у виджет-теста поддельное, и таймер живёт по нему: настоящих пауз
    // здесь не будет.
    testWidgets('сообщение исчезает через отведённое время', (tester) async {
      final toasts = ToastController(duration: const Duration(seconds: 2));
      addTearDown(toasts.dispose);

      toasts.show('Show hidden files: On');
      expect(toasts.current?.message, 'Show hidden files: On');

      await tester.pump(const Duration(seconds: 1));
      expect(toasts.current, isNotNull, reason: 'время ещё не вышло');

      await tester.pump(const Duration(seconds: 2));
      expect(toasts.current, isNull);
    });

    testWidgets('новое сообщение заново заводит время', (tester) async {
      final toasts = ToastController(duration: const Duration(seconds: 2));
      addTearDown(toasts.dispose);

      toasts.show('первое');
      await tester.pump(const Duration(milliseconds: 1500));
      toasts.show('второе');

      // Полторы секунды прошло, но время идёт от последнего сообщения: иначе
      // третье переключение подряд пропадало бы сразу после появления.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(toasts.current?.message, 'второе');

      await tester.pump(const Duration(seconds: 2));
      expect(toasts.current, isNull);
    });

    testWidgets('таймер не переживает приложение', (tester) async {
      ToastController(duration: const Duration(seconds: 2))
        ..show('раз')
        ..dispose();

      // Проверять нечего руками: оставшийся таймер уронит этот тест сам —
      // «A Timer is still pending». В приложении такой пережил бы окно.
    });
  });

  group('на экране', () {
    /// Приложение целиком, со всеми модулями и настоящим окном.
    Future<AppRuntime> pumpApp(WidgetTester tester, {AppSettings? settings}) async {
      final provider = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', size: 10),
        FakeEntry.file('/home/.hidden', size: 1),
      ]);

      final runtime = await testApp(
        provider: provider,
        modules: featureModules(),
        settings: settings,
        toastDuration: const Duration(seconds: 2),
      );

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();
      return runtime;
    }

    /// Нажимает `Cmd-H` — переключение показа скрытых файлов.
    ///
    /// Платформа в виджет-тестах не macOS, поэтому «командная» клавиша здесь
    /// Ctrl: ровно то, во что `KeyCombination` сворачивает `Cmd` вне macOS.
    Future<void> toggleHidden(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
    }

    testWidgets('переключение скрытых файлов говорит о себе', (tester) async {
      final runtime = await pumpApp(
        tester,
        settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
      );
      expect(find.text('Show hidden files: On'), findsNothing);

      await toggleHidden(tester);
      expect(find.text('Show hidden files: On'), findsOneWidget);
      expect(runtime.app.left.showHidden, isTrue);

      // Обратное переключение говорит обратное.
      await toggleHidden(tester);
      expect(find.text('Show hidden files: Off'), findsOneWidget);
      expect(find.text('Show hidden files: On'), findsNothing);

      // И через отведённое время исчезает само.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Show hidden files: Off'), findsNothing);
    });

    testWidgets('сообщение не отнимает места у панелей', (tester) async {
      final runtime = await pumpApp(tester);
      final before = tester.getRect(find.byType(FunctionBar));

      runtime.app.toasts.show('строка, которая никого не двигает');
      await tester.pumpAndSettle();

      expect(find.text('строка, которая никого не двигает'), findsOneWidget);
      // Сообщение висит поверх окна: строка, ради которой прыгает весь экран,
      // раздражает сильнее, чем помогает.
      expect(tester.getRect(find.byType(FunctionBar)), before);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
