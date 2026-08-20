import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/state/error_controller.dart';
import 'package:flex_commander/state/toast_controller.dart';
import 'package:flex_commander/view/dialogs/error_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно, которым приложение сообщает о том, чего не предусмотрело.
void main() {
  late FakeClipboard clipboard;
  late ErrorController errors;
  late ToastController toasts;

  setUp(() {
    clipboard = FakeClipboard();
    errors = ErrorController(clipboard: clipboard, environment: const {'Platform': 'test'});
    toasts = ToastController();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: ErrorLayer(errors: errors, toasts: toasts)),
      ),
    );
    await tester.pump();
  }

  testWidgets('пока ничего не сломалось, окна нет', (tester) async {
    await pump(tester);

    expect(find.text('Unexpected error'), findsNothing);
  });

  testWidgets('ошибка показывается с типом, сообщением и стеком', (tester) async {
    errors.report(StateError('нет такого'), StackTrace.fromString('#0 packing'), 'Packing archive');
    await pump(tester);

    expect(find.text('Unexpected error'), findsOneWidget);
    expect(find.text('StateError'), findsOneWidget);
    expect(find.textContaining('нет такого'), findsWidgets);
    expect(find.textContaining('#0 packing'), findsOneWidget);
    // Контекст — то, чем приложение занималось: без него «Bad state» ни о чём.
    expect(find.text('Packing archive'), findsOneWidget);
  });

  testWidgets('в заголовке видно, что за этой ошибкой есть ещё', (tester) async {
    errors
      ..report(StateError('первая'), StackTrace.fromString('#0 a'))
      ..report(StateError('вторая'), StackTrace.fromString('#0 b'));
    await pump(tester);

    expect(find.text('Unexpected error (1 of 2)'), findsOneWidget);
  });

  testWidgets('Close показывает следующую, а последнюю закрывает', (tester) async {
    errors
      ..report(StateError('первая'), StackTrace.fromString('#0 a'))
      ..report(StateError('вторая'), StackTrace.fromString('#0 b'));
    await pump(tester);

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(find.textContaining('вторая'), findsWidgets);

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(find.text('Unexpected error'), findsNothing);
  });

  testWidgets('Report кладёт отчёт в буфер и говорит об этом', (tester) async {
    // Отправлять пока некуда: «сообщить» — это положить отчёт туда, откуда его
    // можно вставить в задачу или письмо.
    errors.report(StateError('нет такого'), StackTrace.fromString('#0 packing'));
    await pump(tester);

    await tester.tap(find.text('Report'));
    await tester.pump();

    expect(clipboard.text, contains('StateError'));
    expect(clipboard.text, contains('#0 packing'));
    expect(toasts.current?.message, 'Error report copied');
    // Окно не закрылось: отчёт скопирован, а читать его ещё могут.
    expect(find.text('Unexpected error'), findsOneWidget);

    // Сообщение висит на таймере, а незакрытый таймер `flutter_test` считает
    // ошибкой — и до `tearDown` он это проверить успевает.
    toasts.hide();
  });
}
