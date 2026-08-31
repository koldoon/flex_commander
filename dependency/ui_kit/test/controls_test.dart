import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно команды выкладывает содержимое растягивающей колонкой — в ней и
/// проверяются элементы: именно там ширина навязывается силой.
Future<void> pumpInDialogColumn(WidgetTester tester, Widget child, {double width = 400}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const [
          // Значения берутся у оформления по умолчанию: API описывает роли,
          // а красит тема.
          FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
        ],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [child],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('кнопка', () {
    testWidgets('нарисованная кнопка облегает подпись, а не растягивается на всё окно', (tester) async {
      await pumpInDialogColumn(tester, FcButton(label: 'OK', onPressed: () {}), width: 400);

      // Место в колонке кнопке отводится по её ширине — тут не поспоришь,
      // растягивающая колонка задаёт её жёстко. А вот нарисованная кнопка
      // обязана остаться по размеру подписи: раньше она разъезжалась на всё
      // окно, и обойти это можно было только рядом кнопок.
      final painted = find.descendant(of: find.byType(FcButton), matching: find.byType(Opacity));
      expect(tester.getSize(painted).width, lessThan(200));
    });

    testWidgets('в ряду кнопок ширина не меняется', (tester) async {
      await pumpInDialogColumn(
        tester,
        CommandDialogActions(
          actions: [FcButton(label: 'Cancel', onPressed: () {}), FcButton(label: 'OK', onPressed: () {})],
        ),
      );

      final cancel = tester.getSize(find.ancestor(of: find.text('Cancel'), matching: find.byType(FcButton)).first);
      final ok = tester.getSize(find.ancestor(of: find.text('OK'), matching: find.byType(FcButton)).first);
      expect(cancel.width, greaterThan(ok.width));
    });
  });

  group('флажок', () {
    testWidgets('щелчок переключает значение', (tester) async {
      var value = false;
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) =>
                  FcCheckbox(label: 'Follow links', value: value, onChanged: (next) => setState(() => value = next)),
        ),
      );

      await tester.tap(find.text('Follow links'));
      await tester.pump();
      expect(value, isTrue);

      await tester.tap(find.text('Follow links'));
      await tester.pump();
      expect(value, isFalse);
    });

    testWidgets('без обработчика не меняется', (tester) async {
      await pumpInDialogColumn(tester, const FcCheckbox(label: 'Follow links', value: true, onChanged: null));

      await tester.tap(find.text('Follow links'));
      await tester.pump();

      // Показан, но не трогается: щелчок ничего не роняет и ничего не меняет.
      expect(find.text('Follow links'), findsOneWidget);
    });

    testWidgets('нарисованный флажок облегает метку', (tester) async {
      await pumpInDialogColumn(tester, FcCheckbox(label: 'Follow links', value: false, onChanged: (_) {}), width: 400);

      // Иначе щелчок ловился бы далеко за меткой — по всей ширине окна.
      final painted = find.descendant(of: find.byType(FcCheckbox), matching: find.byType(Opacity));
      expect(tester.getSize(painted).width, lessThan(300));
    });
  });

  group('выпадающий список', () {
    testWidgets('раскрывается и выбирает вариант', (tester) async {
      var choice = 'copy';
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) => FcSelect<String>(
                options: const {'copy': 'Copy', 'move': 'Move'},
                value: choice,
                onChanged: (next) => setState(() => choice = next),
              ),
        ),
      );

      // Пока не раскрыт — видно только выбранное: в этом и разница с
      // переключателем, у которого на экране все варианты разом.
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Move'), findsNothing);

      await tester.tap(find.byType(FcSelect<String>));
      await tester.pumpAndSettle();
      expect(find.text('Move'), findsOneWidget);

      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      expect(choice, 'move');
      expect(find.text('Copy'), findsNothing, reason: 'в поле стоит выбранное, а не первое из списка');
    });

    testWidgets('выглядит как поле ввода', (tester) async {
      // Оба отвечают на вопрос «что здесь стоит», и выглядеть должны
      // одинаково: та же высота, та же рамка.
      await pumpInDialogColumn(
        tester,
        Column(
          children: [
            FcSelect<String>(options: const {'copy': 'Copy'}, value: 'copy', onChanged: (_) {}),
            FcTextField(controller: TextEditingController(text: 'Copy')),
          ],
        ),
      );

      expect(tester.getSize(find.byType(FcSelect<String>)).height, tester.getSize(find.byType(FcTextField)).height);
    });

    testWidgets('без обработчика не берёт фокус', (tester) async {
      await pumpInDialogColumn(
        tester,
        const FcSelect<String>(options: {'copy': 'Copy', 'move': 'Move'}, value: 'copy', onChanged: null),
      );

      final focus = tester.widget<Focus>(
        find.descendant(of: find.byType(FcSelect<String>), matching: find.byType(Focus)).first,
      );
      expect(focus.canRequestFocus, isFalse);
    });
  });

  group('переключатель', () {
    testWidgets('выбирается ровно один вариант', (tester) async {
      var choice = 'copy';
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) => FcRadioGroup<String>(
                options: const {'copy': 'Copy', 'move': 'Move'},
                value: choice,
                onChanged: (next) => setState(() => choice = next),
              ),
        ),
      );

      await tester.tap(find.text('Move'));
      await tester.pump();
      expect(choice, 'move');

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(choice, 'copy');
    });

    testWidgets('варианты разделены общим зазором окна', (tester) async {
      // `checkboxGap` здесь не годится: он про расстояние от знака до его
      // метки, внутри варианта. Между вариантами — то же, что между строками
      // окна и кнопками в его ряду.
      await pumpInDialogColumn(
        tester,
        const FcRadioGroup<String>(
          options: {'copy': 'Copy', 'move': 'Move'},
          value: 'copy',
          onChanged: null,
          direction: Axis.horizontal,
        ),
      );

      final Rect first = tester.getRect(find.text('Copy'));
      final Rect second = tester.getRect(find.text('Move'));
      final double gap = const DefaultMetrics().dialogGap;

      // Между вариантами: конец подписи, знак второго и зазоры вокруг него.
      expect(second.left - first.right, greaterThanOrEqualTo(gap));
    });

    testWidgets('порядок вариантов — порядок карты', (tester) async {
      await pumpInDialogColumn(
        tester,
        const FcRadioGroup<String>(
          options: {'copy': 'Copy', 'move': 'Move', 'link': 'Link'},
          value: 'copy',
          onChanged: null,
        ),
      );

      final copy = tester.getTopLeft(find.text('Copy')).dy;
      final move = tester.getTopLeft(find.text('Move')).dy;
      final link = tester.getTopLeft(find.text('Link')).dy;
      expect(copy, lessThan(move));
      expect(move, lessThan(link));
    });
  });

  group('текст', () {
    testWidgets('подпись и значение набираются разными стилями', (tester) async {
      await pumpInDialogColumn(tester, const Column(children: [FcLabel('Copy to'), FcText('/home/docs')]));

      final label = tester.widget<Text>(find.text('Copy to'));
      final text = tester.widget<Text>(find.text('/home/docs'));
      expect(label.style?.color, isNot(text.style?.color));
    });

    testWidgets('сообщение об ошибке набирается цветом ошибки', (tester) async {
      await pumpInDialogColumn(tester, const FcErrorText(message: 'Permission denied'));

      final text = tester.widget<Text>(find.text('Permission denied'));
      expect(text.style?.color, const DefaultColors().error);
    });
  });

  group('переключатель в ряд', () {
    testWidgets('переносится, а не вылезает за край', (tester) async {
      // Сколько места дадут — модуль не знает, и ряд с длинными подписями
      // должен переноситься, а не рисовать полосатую «переполненность».
      await pumpInDialogColumn(
        tester,
        const FcRadioGroup<String>(
          direction: Axis.horizontal,
          options: {'a': 'Store', 'b': 'Fast', 'c': 'Normal', 'd': 'Best'},
          value: 'a',
          onChanged: null,
        ),
        width: 200,
      );

      expect(tester.takeException(), isNull);
      for (final title in ['Store', 'Fast', 'Normal', 'Best']) {
        expect(find.text(title), findsOneWidget);
      }
    });
  });
}
