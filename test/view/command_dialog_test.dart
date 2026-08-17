import 'package:flex_commander/view/dialogs/command_dialog.dart';
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
        theme: AppTheme.theme,
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

  testWidgets('пока ничего не посчитано, счётчика нет, а полоса неопределённая', (tester) async {
    await pumpProgress(tester);

    expect(find.textContaining(' of '), findsNothing);
    expect(tester.widget<FcProgressBar>(find.byType(FcProgressBar)).value, isNull);
  });
}
