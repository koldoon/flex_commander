import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно хода работы: что именно видит пользователь, пока идёт копирование.
/// Оформление, которым рисуется окно в тестах.
const _defaultTheme = FcThemeSpec(
  id: 'default',
  title: 'Default',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

/// Свои варианты ответа: окно рисует те, что ему дали, и ни одного не знает
/// по имени — потому тест и объявляет их сам.
const _overwrite = OperationRequestOption('overwrite', 'Overwrite');
const _skip = OperationRequestOption('skip', 'Skip');
const _retry = OperationRequestOption('retry', 'Retry');
const _cancel = OperationRequestOption('cancel', 'Cancel');

void main() {
  Future<void> pumpProgress(
    WidgetTester tester, {
    String message = 'Copying notes.txt…',
    double? progress,
    int processed = 0,
    int? total,
    bool totalIsFinal = true,
    String itemName = '',
    double? itemProgress,
    int itemBytes = 0,
    int? itemTotalBytes,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_defaultTheme),
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
              itemName: itemName,
              itemProgress: itemProgress,
              itemBytes: itemBytes,
              itemTotalBytes: itemTotalBytes,
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
    (widget) => widget is DecoratedBox && (widget.decoration as BoxDecoration).color == const DefaultColors().progress,
  );

  testWidgets('закрашенная часть видна и занимает свою долю', (tester) async {
    await pumpProgress(tester, processed: 1, total: 2, progress: 0.5);

    const metrics = DefaultMetrics();
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
          theme: buildThemeData(_defaultTheme),
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
      options: const [_retry, _cancel],
      enterOption: _retry,
      inputLabel: 'Password:',
      secret: secret,
    );

    testWidgets('вопрос без поля остаётся набором кнопок', (tester) async {
      await pumpQuestion(
        tester,
        OperationRequest(message: 'Already exists', options: const [_skip, _cancel], enterOption: _skip),
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

      expect(await request.answer, _retry);
      expect(request.text, 'secret');
    });

    testWidgets('Enter в поле отвечает вариантом по умолчанию', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(await request.answer, _retry);
      expect(request.text, 'secret');
    });

    testWidgets('отказ отвечает без текста', (tester) async {
      await pumpQuestion(tester, passwordRequest());

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));

      expect(await request.answer, _cancel);
    });

    testWidgets('подсвечена та кнопка, которую нажмёт Enter', (tester) async {
      await pumpQuestion(
        tester,
        OperationRequest(message: 'Already exists', options: const [_overwrite, _skip, _cancel], enterOption: _skip),
      );

      // Не первая по порядку: молча затирать чужие файлы нельзя.
      expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Skip')).primary, isTrue);
      expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Overwrite')).primary, isFalse);
    });
  });

  group('ход текущего объекта', () {
    testWidgets('блока объекта нет, пока не о чем рассказывать', (tester) async {
      await pumpProgress(tester, processed: 3, total: 10, progress: 0.3);

      // Удаление в корзину, работа без байтов — показывать по объекту нечего.
      expect(find.byType(FcProgressBar), findsOneWidget);
      expect(find.text('File'), findsNothing);
    });

    testWidgets('у текущего объекта свой бар и своя строка объёма', (tester) async {
      await pumpProgress(
        tester,
        processed: 3,
        total: 10,
        progress: 0.3,
        itemName: 'movie.mkv',
        itemProgress: 0.25,
        itemBytes: 1024 * 1024,
        itemTotalBytes: 4 * 1024 * 1024,
      );

      // Работа из тысячи мелких файлов и работа из одного огромного в общем
      // счёте выглядят одинаково — вот это их и различает.
      expect(find.byType(FcProgressBar), findsNWidgets(2));
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      // Имя, объём и полоса — три строки под одной подписью, каждая своя.
      expect(find.text('movie.mkv'), findsOneWidget);
      expect(find.text('1.0 MB of 4.0 MB'), findsOneWidget);
    });

    testWidgets('имя объекта показано без пути', (tester) async {
      // Внутри архива у записи путь длинный, а толку от него нет: где лежит
      // работа — сказано строкой выше, в «Item».
      await pumpProgress(
        tester,
        progress: 0.3,
        itemName: 'bin/cache/artifacts/engine/darwin-x64/engine.stamp',
        itemProgress: 0.5,
        itemTotalBytes: 100,
      );

      expect(find.text('engine.stamp'), findsOneWidget);
      expect(find.textContaining('darwin-x64'), findsNothing);
    });

    testWidgets('длинное имя обрезается, а не переносится', (tester) async {
      // Иначе окно росло бы вниз на каждом длинном имени.
      await pumpProgress(
        tester,
        progress: 0.3,
        itemName: 'a-very-long-name-that-would-have-stretched-the-dialog-down-a-line.txt',
        itemProgress: 0.5,
        itemTotalBytes: 100,
      );

      final name = tester.widget<Text>(
        find.text('a-very-long-name-that-would-have-stretched-the-dialog-down-a-line.txt'),
      );
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
    });

    testWidgets('бар объекта показывает свою долю, а не общую', (tester) async {
      await pumpProgress(tester, progress: 0.3, itemName: 'big.bin', itemProgress: 0.75, itemTotalBytes: 100);

      final bars = tester.widgetList<FcProgressBar>(find.byType(FcProgressBar)).toList();
      expect(bars.first.value, 0.75);
      expect(bars.last.value, 0.3);
    });
  });
}
