import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Мигание нарисованного курсора: там, где системного поля ввода нет.
///
/// Кадры здесь прокручиваются **вручную** (`pump` с длительностью), а не
/// `pumpAndSettle`: покоя у мигания не бывает по определению, и ждать его —
/// значит ждать вечно. Ровно поэтому `testApp` мигание и выключает; здесь же
/// проверяется само оно, и выключать его нельзя.
void main() {
  /// Что нарисовано сейчас: `true` — курсор виден.
  Future<void> pumpCursor(WidgetTester tester, {Object? resetOn}) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FcCursorBlink(resetOn: resetOn, builder: (context, visible) => Text(visible ? 'on' : 'off')),
      ),
    );
  }

  /// Убирает виджет, а вместе с ним и таймер: переживший тест таймер роняет
  /// прогон — и правильно делает.
  Future<void> remove(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

  setUp(() => FcCursorBlink.debugDeterministicCursor = false);
  tearDown(() => FcCursorBlink.debugDeterministicCursor = false);

  testWidgets('курсор мигает: полсекунды виден, полсекунды нет', (tester) async {
    await pumpCursor(tester);
    expect(find.text('on'), findsOneWidget, reason: 'появился видимым');

    await tester.pump(FcCursorBlink.halfPeriod);
    expect(find.text('off'), findsOneWidget);

    await tester.pump(FcCursorBlink.halfPeriod);
    expect(find.text('on'), findsOneWidget);

    await remove(tester);
  });

  testWidgets('набор сбрасывает мигание: пока печатают, курсор виден', (tester) async {
    await pumpCursor(tester, resetOn: 'do');
    await tester.pump(FcCursorBlink.halfPeriod);
    expect(find.text('off'), findsOneWidget, reason: 'успел погаснуть');

    // Набрали ещё букву — курсор обязан быть на виду, а не пропадать посреди
    // набора на полсекунды.
    await pumpCursor(tester, resetOn: 'dow');
    expect(find.text('on'), findsOneWidget);

    // И отсчёт пошёл заново, а не продолжился с прежнего места.
    await tester.pump(FcCursorBlink.halfPeriod - const Duration(milliseconds: 1));
    expect(find.text('on'), findsOneWidget);

    await remove(tester);
  });

  testWidgets('выключенное мигание оставляет курсор видимым и даёт дождаться покоя', (tester) async {
    // Так его выключает `testApp` — один раз и за все тесты.
    FcCursorBlink.debugDeterministicCursor = true;

    await pumpCursor(tester);
    // Ни одного кадра больше не запланировано — иначе `pumpAndSettle` не
    // вернулся бы отсюда никогда.
    await tester.pumpAndSettle();

    expect(find.text('on'), findsOneWidget);

    await tester.pump(FcCursorBlink.halfPeriod * 4);
    expect(find.text('on'), findsOneWidget, reason: 'и дальше не гаснет');

    await remove(tester);
  });
}
