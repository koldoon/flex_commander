import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Пометка правой кнопкой: щелчок переключает строку, протягивание помечает
/// отрезок (`spec/mouse-marking.md`).
void main() {
  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/deep'),
      for (var i = 0; i < 40; i++) FakeEntry.file('/home/file-${i.toString().padLeft(2, '0')}.txt', size: 1),
      FakeEntry.file('/home/deep/inside.txt', size: 1),
    ])..home = '/home';

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1312, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Строка **левой** панели по имени: в правой открыт тот же каталог, и по
  /// одному имени нашлись бы две строки.
  Finder row(String name) => find.descendant(
    of: find.byType(FileTable).first,
    matching: find.byWidgetPredicate((widget) => widget is FileTableRow && widget.node.name == name),
  );

  Set<String> marked() => app.left.selection.names;

  /// Нажать правой на строке, провести по перечисленным и отпустить.
  Future<void> markThrough(WidgetTester tester, String from, {List<String> through = const []}) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: tester.getCenter(row(from)));
    await tester.pump();
    await mouse.down(tester.getCenter(row(from)));
    await tester.pump(const Duration(milliseconds: 20));
    for (final name in through) {
      await mouse.moveTo(tester.getCenter(row(name)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();
  }

  testWidgets('щелчок правой помечает строку и ставит на неё курсор', (tester) async {
    await pumpApp(tester);

    await markThrough(tester, 'file-03.txt');

    expect(marked(), {'file-03.txt'});
    expect(app.left.currentNode?.name, 'file-03.txt');

    // Второй щелчок по той же строке пометку снимает.
    await markThrough(tester, 'file-03.txt');

    expect(marked(), isEmpty);
  });

  testWidgets('протягивание помечает отрезок целиком', (tester) async {
    await pumpApp(tester);

    await markThrough(tester, 'file-02.txt', through: ['file-04.txt', 'file-06.txt']);

    // Обе крайние строки входят, пропущенные по дороге — тоже: считается
    // отрезок, а не след указателя.
    expect(marked(), {'file-02.txt', 'file-03.txt', 'file-04.txt', 'file-05.txt', 'file-06.txt'});
    expect(app.left.currentNode?.name, 'file-06.txt');
  });

  testWidgets('ход назад возвращает лишние строки как было', (tester) async {
    await pumpApp(tester);

    await markThrough(tester, 'file-02.txt', through: ['file-08.txt', 'file-04.txt']);

    expect(marked(), {'file-02.txt', 'file-03.txt', 'file-04.txt'});
  });

  testWidgets('жест с помеченной строки снимает пометку по всему отрезку', (tester) async {
    await pumpApp(tester);
    await markThrough(tester, 'file-01.txt', through: ['file-06.txt']);
    expect(marked(), hasLength(6));

    // Начали с помеченной — значит, снимаем; и только по отрезку.
    await markThrough(tester, 'file-02.txt', through: ['file-04.txt']);

    expect(marked(), {'file-01.txt', 'file-05.txt', 'file-06.txt'});
  });

  testWidgets('«..» не помечается ни при каком направлении', (tester) async {
    await pumpApp(tester);
    await app.left.openPath('/home/deep');
    await tester.pumpAndSettle();

    await markThrough(tester, '..', through: ['inside.txt']);

    expect(marked(), {'inside.txt'});
    expect(app.left.selection.length, 1);
  });

  testWidgets('правая по заголовку колонки пометку не трогает', (tester) async {
    await pumpApp(tester);

    final header = find.descendant(of: find.byType(FileTableHeader).first, matching: find.text('Name')).first;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: tester.getCenter(header));
    await tester.pump();
    await mouse.down(tester.getCenter(header));
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(marked(), isEmpty);
    // Меню видимости колонок при этом открывается, как и раньше.
    expect(find.text('Size'), findsWidgets);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();
  });

  testWidgets('у нижнего края список едет сам и отрезок дотягивается дальше экрана', (tester) async {
    await pumpApp(tester);

    final table = find.byType(FileTable).first;
    final bottom = tester.getRect(table).bottom;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: tester.getCenter(row('file-00.txt')));
    await tester.pump();
    await mouse.down(tester.getCenter(row('file-00.txt')));
    await tester.pump(const Duration(milliseconds: 20));

    // Указатель ушёл далеко за нижний край и стоит — список обязан ехать сам.
    await mouse.moveTo(Offset(tester.getCenter(table).dx, bottom + 100));
    await tester.pump(const Duration(milliseconds: 20));
    final markedAtEdge = marked().length;

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final rolled = marked().length;

    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();

    expect(rolled, greaterThan(markedAtEdge), reason: 'список стоял на месте');
    expect(marked(), contains('file-00.txt'), reason: 'отрезок считается от начальной строки');
    // Помечено непрерывно от начала: ни одна строка по дороге не пропущена.
    expect(marked(), containsAll([for (var i = 0; i < rolled; i++) 'file-${i.toString().padLeft(2, '0')}.txt']));
  });
}
