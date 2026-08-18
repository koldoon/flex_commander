import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно хода работы: что именно видит пользователь, пока идёт копирование.
void main() {
  Future<void> pumpProgress(
    WidgetTester tester, {
    String message = 'Copying notes.txt…',
    double? progress,
    int processed = 0,
    int? total,
    bool totalIsFinal = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(FcThemeSpec.fallback),
        home: Scaffold(
          // Окно команды меряет себя по содержимому — в рамке стоит
          // `IntrinsicWidth`. Без него измерение здесь не воспроизводится,
          // и виджеты, которые его не переживают, проходят мимо тестов.
          body: IntrinsicWidth(
            child: CommandDialogProgress(
              message: message,
              progress: progress,
              processed: processed,
              total: total,
              totalIsFinal: totalIsFinal,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('видно имя того, что копируется прямо сейчас', (tester) async {
    await pumpProgress(tester, processed: 3, total: 10, progress: 0.3);

    expect(find.text('Copying notes.txt…'), findsOneWidget);
  });

  testWidgets('видно, сколько объектов обработано из скольких', (tester) async {
    await pumpProgress(tester, processed: 3, total: 10, progress: 0.3);

    expect(find.text('3 of 10'), findsOneWidget);
    expect(tester.widget<FcProgressBar>(find.byType(FcProgressBar)).value, 0.3);
  });

  testWidgets('пока идёт подсчёт, итог помечен как неокончательный', (tester) async {
    await pumpProgress(tester, processed: 3, total: 10, progress: 0.3, totalIsFinal: false);

    // Растущее число не должно выглядеть ошибкой.
    expect(find.text('3 of 10…'), findsOneWidget);
  });

  /// Закрашенная часть полосы: `DecoratedBox`, залитый цветом хода работы.
  /// Внешняя рамка полосы — тоже `DecoratedBox`, но она без заливки.
  Finder progressFill() => find.byWidgetPredicate(
    (widget) => widget is DecoratedBox && (widget.decoration as BoxDecoration).color == const FcColors().progress,
  );

  testWidgets('закрашенная часть видна и занимает свою долю', (tester) async {
    await pumpProgress(tester, processed: 1, total: 2, progress: 0.5);

    const metrics = FcMetrics();
    final bar = tester.getSize(find.byType(FcProgressBar));
    final fill = tester.getSize(progressFill());
    // Заливка лежит внутри обводки и отступа.
    final inset = 2 * (metrics.strokeWidth + metrics.progressInset);

    // Полоса заливается на всю свою высоту: у пустого `DecoratedBox` своей
    // высоты нет, и без растяжения от заливки осталась бы нулевая полоска.
    expect(fill.height, greaterThan(0));
    expect(fill.height, closeTo(bar.height - inset, 0.01));
    expect(fill.width, closeTo((bar.width - inset) / 2, 1));
  });

  testWidgets('при неизвестной доле полоса пуста', (tester) async {
    await pumpProgress(tester);

    expect(progressFill(), findsNothing);
  });

  testWidgets('пока ничего не посчитано, счётчика нет, а полоса неопределённая', (tester) async {
    await pumpProgress(tester);

    expect(find.textContaining(' of '), findsNothing);
    expect(tester.widget<FcProgressBar>(find.byType(FcProgressBar)).value, isNull);
  });
  group('вопрос с вводом строки', () {
    late OperationRequest request;
    late String answered;

    Future<void> pumpQuestion(WidgetTester tester, OperationRequest it) {
      request = it;
      answered = '';
      return tester.pumpWidget(
        MaterialApp(
          theme: buildThemeData(FcThemeSpec.fallback),
          home: Scaffold(
            body: IntrinsicWidth(
              child: Builder(
                builder:
                    (context) => CommandDialogQuestion(
                      request: it,
                      onAnswer: (option) => it.respond(option, text: answered),
                      onTextChanged: (value) => answered = value,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    OperationRequest passwordRequest({bool secret = true}) => OperationRequest(
      message: 'archive.zip is encrypted',
      options: const [OperationOption.retry, OperationOption.cancel],
      defaultOption: OperationOption.retry,
      inputLabel: 'Password:',
      secret: secret,
    );

    testWidgets('вопрос без поля остаётся набором кнопок', (tester) async {
      await pumpQuestion(
        tester,
        OperationRequest(message: 'Already exists', options: const [OperationOption.skip, OperationOption.cancel]),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Already exists'), findsOneWidget);
    });

    testWidgets('поле появляется с подписью и берёт фокус', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      expect(find.text('Password:'), findsOneWidget);
      // Набирать можно сразу, без клика по полю.
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    });

    testWidgets('пароль не показывается', (tester) async {
      await pumpQuestion(tester, passwordRequest());
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);

      await pumpQuestion(tester, passwordRequest(secret: false));
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    });

    testWidgets('набранное доходит до того, кто спрашивал', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FcButton, 'Retry'));

      expect(await request.answer, OperationOption.retry);
      expect(request.text, 'secret');
    });

    testWidgets('Enter в поле отвечает вариантом по умолчанию', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(await request.answer, OperationOption.retry);
      expect(request.text, 'secret');
    });

    testWidgets('отказ отвечает без текста', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));

      expect(await request.answer, OperationOption.cancel);
    });

    testWidgets('подсвечена та кнопка, которую нажмёт Enter', (tester) async {
      await pumpQuestion(
        tester,
        OperationRequest(
          message: 'Already exists',
          options: const [OperationOption.overwrite, OperationOption.skip, OperationOption.cancel],
          defaultOption: OperationOption.skip,
        ),
      );

      // Не первая по порядку: молча затирать чужие файлы нельзя.
      expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Skip')).primary, isTrue);
      expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Overwrite')).primary, isFalse);
    });
  });
}
