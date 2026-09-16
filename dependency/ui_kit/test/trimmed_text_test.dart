import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обрезанное договаривается подсказкой, поместившееся — молчит
/// (`docs/spec/tooltips.md`, §2).
void main() {
  const style = TextStyle(fontSize: 14);
  const short = 'readme.md';
  const long = 'невероятно длинное имя файла, которому не хватит ширины.txt';
  const path = '/Users/koldoon/Developer/Petrosoft/qwickserve/dist';

  Future<void> pump(WidgetTester tester, Widget child) => pumpScreen(tester, Align(child: child));

  testWidgets('поместившийся текст подсказки не заводит', (tester) async {
    await pump(tester, const FcTrimmedText(text: short, style: style, width: 400));

    expect(find.byType(FcTooltip), findsNothing, reason: 'не «есть, но пустая», а нет вовсе');

    await disposeScreen(tester);
  });

  testWidgets('обрезанный договаривается целиком', (tester) async {
    await pump(tester, const FcTrimmedText(text: long, style: style, width: 60));

    expect(tester.widget<FcTooltip>(find.byType(FcTooltip)).message, long);

    await disposeScreen(tester);
  });

  testWidgets('многоточие ставит ellipsis, а не мы', (tester) async {
    await pump(tester, const FcTrimmedText(text: long, style: style, width: 60));

    final shown = tester.widget<Text>(find.byType(Text));
    expect(shown.data, long, reason: 'рисование не меняется ни на точку — режет ellipsis');
    expect(shown.maxLines, 1);
    expect(shown.overflow, TextOverflow.ellipsis);

    await disposeScreen(tester);
  });

  testWidgets('ширина числом и своя раскладка дают один ответ', (tester) async {
    await pump(tester, const SizedBox(width: 60, child: FcTrimmedText(text: long, style: style)));
    expect(find.byType(FcTooltip), findsOneWidget, reason: 'не поместилось и без подсказанной ширины');

    await pump(tester, const SizedBox(width: 600, child: FcTrimmedText(text: short, style: style)));
    expect(find.byType(FcTooltip), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('путь режется слева, а подсказка показывает его целиком', (tester) async {
    await pump(tester, const FcTrimmedText(text: path, style: style, width: 120, side: FcTrimSide.head));

    final shown = tester.widget<Text>(find.byType(Text));
    expect(shown.data, startsWith('/…'), reason: 'корень остаётся: по нему видно, о каком диске речь');
    expect(shown.data, endsWith('dist'));
    expect(tester.widget<FcTooltip>(find.byType(FcTooltip)).message, path);

    await disposeScreen(tester);
  });

  testWidgets('путь поместился — подсказки нет', (tester) async {
    await pump(tester, const FcTrimmedText(text: path, style: style, width: 4000, side: FcTrimSide.head));

    expect(find.byType(FcTooltip), findsNothing);
    expect(tester.widget<Text>(find.byType(Text)).data, path);

    await disposeScreen(tester);
  });

  testWidgets('окно облегает содержимое — виджет не мерит и не падает', (tester) async {
    // Так рама окна меряет своё содержимое; `LayoutBuilder` на этот вопрос
    // отвечать не умеет (`docs/spec/dialog-body.md`).
    await pump(tester, const IntrinsicWidth(child: FcTrimmedText(text: long, style: style, hugged: true)));

    expect(tester.takeException(), isNull);
    expect(find.byType(FcTooltip), findsNothing, reason: 'окно ровно такой ширины, какой хватило');

    await disposeScreen(tester);
  });

  testWidgets('подсказка выше по дереву — второй не заводится', (tester) async {
    await pump(
      tester,
      const FcTooltip(
        message: 'плашка договаривает о всём месте',
        child: SizedBox(width: 60, child: FcTrimmedText(text: long, style: style)),
      ),
    );

    expect(find.byType(FcTooltip), findsOneWidget, reason: 'вложенные всплывали бы обе');

    await disposeScreen(tester);
  });

  testWidgets('две строки: влезшее в них молчит, не влезшее договаривается', (tester) async {
    // Имя под значком в сетке занимает две строки всегда — влезло оно в одну
    // или нет (`docs/spec/panel-view-icons.md`, §4).
    const two = 'имя из двух строк';
    await pump(tester, const FcTrimmedText(text: two, style: style, width: 200, maxLines: 2));
    expect(find.byType(FcTooltip), findsNothing, reason: 'в две строки влезло');
    expect(tester.widget<Text>(find.byType(Text)).maxLines, 2);

    await pump(tester, const FcTrimmedText(text: long, style: style, width: 120, maxLines: 2));
    expect(tester.widget<FcTooltip>(find.byType(FcTooltip)).message, long, reason: 'и в две не влезло');

    await disposeScreen(tester);
  });

  testWidgets('пустой текст молчит', (tester) async {
    await pump(tester, const FcTrimmedText(text: '', style: style, width: 0));

    expect(find.byType(FcTooltip), findsNothing);

    await disposeScreen(tester);
  });
}
