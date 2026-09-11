import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        FcDialogActions(
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

  group('флажок с третьим состоянием', () {
    const icons = DefaultIcons();

    /// Что нарисовано в клетке: галочка, чёрточка или ничего.
    String? markIn(WidgetTester tester) {
      final texts = tester.widgetList<Text>(find.descendant(of: find.byType(FcCheckbox), matching: find.byType(Text)));
      for (final text in texts) {
        if (text.style?.fontFamily == icons.fontFamily) {
          return text.data;
        }
      }
      return null;
    }

    Future<void> pumpTristate(WidgetTester tester, {bool? initial}) async {
      var value = initial;
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) => FcCheckbox.tristate(
                label: 'Execute',
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
        ),
      );
    }

    testWidgets('обход замкнут: смешанное → включено → выключено → смешанное', (tester) async {
      await pumpTristate(tester);

      expect(markIn(tester), icons.glyph(icons.mixed), reason: 'начали со смешанного');

      await tester.tap(find.text('Execute'));
      await tester.pump();
      expect(markIn(tester), icons.glyph(icons.check));

      await tester.tap(find.text('Execute'));
      await tester.pump();
      expect(markIn(tester), isNull, reason: 'выключено — пустая клетка');

      // Круг замкнут нарочно: передумав, человек возвращает «не трогать», не
      // закрывая окна.
      await tester.tap(find.text('Execute'));
      await tester.pump();
      expect(markIn(tester), icons.glyph(icons.mixed));
    });

    testWidgets('Space водит по тому же кругу, что и щелчок', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      bool? value;
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) => FcCheckbox.tristate(
                label: 'Execute',
                value: value,
                focusNode: focus,
                onChanged: (next) => setState(() => value = next),
              ),
        ),
      );

      focus.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(markIn(tester), icons.glyph(icons.check));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(markIn(tester), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(markIn(tester), icons.glyph(icons.mixed));
    });

    testWidgets('обычный флажок в смешанное не попадает', (tester) async {
      var value = true;
      await pumpInDialogColumn(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) =>
                  FcCheckbox(label: 'Execute', value: value, onChanged: (next) => setState(() => value = next)),
        ),
      );

      // Ему это и не выразить: обратный вызов у него `bool`, а не `bool?`.
      await tester.tap(find.text('Execute'));
      await tester.pump();
      expect(markIn(tester), isNull);

      await tester.tap(find.text('Execute'));
      await tester.pump();
      expect(markIn(tester), icons.glyph(icons.check));
    });

    testWidgets('без обработчика не меняется и в смешанном', (tester) async {
      await pumpInDialogColumn(tester, const FcCheckbox.tristate(label: 'Execute', value: null, onChanged: null));

      await tester.tap(find.text('Execute'));
      await tester.pump();

      expect(markIn(tester), icons.glyph(icons.mixed));
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

      await tester.tap(find.descendant(of: find.byType(FcSelect<String>), matching: find.byType(Opacity)));
      await tester.pumpAndSettle();

      // Строка списка набрана разметкой — тем же `FcPickList`, что в палитре и
      // в оглавлении настроек, — поэтому ищется через `findRichText`.
      final option = find.text('Move', findRichText: true);
      expect(option, findsOneWidget);

      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(choice, 'move');
      expect(find.text('Copy'), findsNothing, reason: 'в поле стоит выбранное, а не первое из списка');
    });

    testWidgets('раскрытая часть ровно по ширине рамки', (tester) async {
      await pumpInDialogColumn(
        tester,
        FcSelect<String>(
          options: const {'copy': 'Copy', 'move': 'Move to another panel'},
          value: 'copy',
          onChanged: (_) {},
        ),
      );

      // Видимая рамка, а не внешний бокс: тот растянут колонкой окна.
      final frame = find.descendant(of: find.byType(FcSelect<String>), matching: find.byType(Opacity));
      final field = tester.getRect(frame);
      await tester.tap(frame);
      await tester.pumpAndSettle();

      // Раскрытая часть ровно по ширине рамки.
      expect(tester.getSize(find.byType(CompositedTransformFollower)).width, field.width);

      // И встаёт **под** полем, а не рядом. Место спрашивается у списка, а не у
      // самой раскрытой части: та стоит в наложении и о том, куда её сдвинули
      // вслед за полем, узнаёт только при отрисовке.
      final border = const DefaultMetrics().strokeWidth;
      final list = tester.getRect(find.byType(FcPickList));
      expect(list.left, field.left + border);
      expect(list.width, field.width - border * 2);
      expect(list.top, greaterThan(field.bottom));
    });

    testWidgets('щелчок мимо закрывает список, ничего не выбрав', (tester) async {
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

      await tester.tap(find.descendant(of: find.byType(FcSelect<String>), matching: find.byType(Opacity)));
      await tester.pumpAndSettle();
      expect(find.byType(FcPickList), findsOneWidget);

      // Как затенение закрывает окно: мимо — значит передумал, а не выбрал
      // первое попавшееся.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(FcPickList), findsNothing);
      expect(choice, 'copy');
    });

    testWidgets('ширина — по самому длинному варианту, а не во всю строку', (tester) async {
      await pumpInDialogColumn(
        tester,
        FcSelect<String>(
          options: const {'copy': 'Copy', 'move': 'Move to another panel'},
          value: 'copy',
          onChanged: (_) {},
        ),
        width: 400,
      );

      // Ни во всю колонку (иначе обещало бы место, которому нечем заполниться),
      // ни по выбранному (иначе поле прыгало бы при смене варианта).
      final width =
          tester.getSize(find.descendant(of: find.byType(FcSelect<String>), matching: find.byType(Opacity))).width;
      expect(width, lessThan(300));
      expect(width, greaterThan(120));
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

  group('переключатель', () {});

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

  group('переключатель в ряд', () {});
}
