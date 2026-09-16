import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сведения в панели: плашки разделов, доли столбцов и перенос вместо ленты
/// вбок (`docs/spec/file-info.md`).
void main() {
  /// Имя нарочно длинное и без пробелов: такое значение перенос обычным
  /// правилом не разорвать, и раньше ради него таблицу листали вбок.
  const long = 'снимок-экрана-2026-09-16-в-21.23.59-очень-длинное-имя-без-пробелов.dat';

  Future<void> open(WidgetTester tester) async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/$long', size: 3 * 1024 * 1024, modified: DateTime(2026, 9, 6)),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.left.setCursorToName(long);
    runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// Первая таблица сведений — та, что в панели.
  Table tableOf(WidgetTester tester) =>
      tester.widget<Table>(find.descendant(of: find.byType(FileInfoView), matching: find.byType(Table)).first);

  testWidgets('столбцы делят ширину как 2 к 3', (tester) async {
    await open(tester);

    final table = tableOf(tester);
    final cells = table.children.first.children;
    final label = tester.getRect(find.byWidget(cells[0]));
    final value = tester.getRect(find.byWidget(cells[1]));

    expect(
      value.width / label.width,
      closeTo(FcKeyValueSections.valueShare / FcKeyValueSections.labelShare, 0.1),
      reason: 'подпись — короткое название поля, значению место нужнее',
    );
  });

  testWidgets('длинное значение переносится, а не уезжает вбок', (tester) async {
    await open(tester);

    final shown = find.descendant(of: find.byType(FileInfoView), matching: find.text(long));
    expect(shown, findsOneWidget, reason: 'имя показано целиком, без многоточия');

    final table = tableOf(tester);
    final value = tester.getRect(find.byWidget(table.children.first.children[1]));
    final text = tester.getRect(shown);

    expect(text.width, lessThanOrEqualTo(value.width + 0.5), reason: 'текст остался в своём столбце');
    expect(text.height, greaterThan(20), reason: 'значит, лёг несколькими строками');
  });

  testWidgets('вбок сведения не листаются вовсе', (tester) async {
    await open(tester);

    final sideways = find.descendant(
      of: find.byType(FileInfoView),
      matching: find.byWidgetPredicate(
        (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(sideways, findsNothing, reason: 'перенос заменил ленту вбок');
  });

  testWidgets('разделы стоят в плашках, как в справке и настройках', (tester) async {
    await open(tester);

    final sections = tester.widget<FcKeyValueSections>(
      find.descendant(of: find.byType(FileInfoView), matching: find.byType(FcKeyValueSections)),
    );
    expect(sections.divided, isTrue);
    expect(sections.bounded, isTrue);
  });
}
