import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/commands/help_command.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно команды тянут за края и углы, и размер переживает закрытие.
///
/// Окно берётся настоящее — справка: она объявила себя тянущейся и назвала
/// себя (`docs/spec/dialog-resize.md`).
void main() {
  late AppRuntime runtime;

  Future<AppRuntime> build({AppSettings? settings}) => testApp(
    provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
    modules: featureModules(),
    settings: settings ?? AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
  );

  setUp(() async => runtime = await build());

  Future<void> start(WidgetTester tester, {Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  Future<void> openHelp(WidgetTester tester) async {
    runtime.commands.run(HelpCommand.commandId);
    await tester.pumpAndSettle();
  }

  /// Само окно — то, что внутри рамы.
  Rect window(WidgetTester tester) =>
      tester.getRect(find.descendant(of: find.byType(DialogFrame), matching: find.byType(DialogWidth)));

  FcMetrics metrics(WidgetTester tester) => FcTheme.of(tester.element(find.byType(DialogFrame))).metrics;

  /// Тянуть от точки, шагами: одно движение только начинает протяжку.
  Future<void> dragFrom(WidgetTester tester, Offset from, Offset by) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: from);
    await tester.pump();
    await mouse.down(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var step = 1; step <= 5; step++) {
      await mouse.moveTo(from + by * (step / 5));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();
  }

  /// Точка на краю окна — внутри полосы захвата.
  Offset edgeOf(Rect box, {double? left, double? right, double? top, double? bottom}) => Offset(
    left != null
        ? box.left + left
        : right != null
        ? box.right - right
        : box.center.dx,
    top != null
        ? box.top + top
        : bottom != null
        ? box.bottom - bottom
        : box.center.dy,
  );

  group('края', () {
    testWidgets('правый край расширяет окно, левый остаётся на месте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, right: 2), const Offset(120, 0));

      final after = window(tester);
      expect(after.width - before.width, moreOrLessEquals(120, epsilon: 2));
      expect(after.left, moreOrLessEquals(before.left, epsilon: 2), reason: 'левый край уехал');
    });

    testWidgets('левый край расширяет окно, правый остаётся на месте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, left: 2), const Offset(-120, 0));

      final after = window(tester);
      expect(after.width - before.width, moreOrLessEquals(120, epsilon: 2));
      expect(after.right, moreOrLessEquals(before.right, epsilon: 2), reason: 'правый край уехал');
    });

    testWidgets('нижний край растит окно вниз, верх остаётся на месте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, bottom: 2), const Offset(0, 100));

      final after = window(tester);
      expect(after.height - before.height, moreOrLessEquals(100, epsilon: 2));
      expect(after.top, moreOrLessEquals(before.top, epsilon: 2));
    });

    testWidgets('верхний край растит окно вверх, низ остаётся на месте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, top: 2), const Offset(0, -80));

      final after = window(tester);
      expect(after.height - before.height, moreOrLessEquals(80, epsilon: 2));
      expect(after.bottom, moreOrLessEquals(before.bottom, epsilon: 2), reason: 'низ уехал');
    });

    testWidgets('угол тянет по двум осям разом', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, right: 2, bottom: 2), const Offset(90, 70));

      final after = window(tester);
      expect(after.width - before.width, moreOrLessEquals(90, epsilon: 2));
      expect(after.height - before.height, moreOrLessEquals(70, epsilon: 2));
    });
  });

  group('пределы', () {
    testWidgets('ниже предела окно не ужимается', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      // Тянем заведомо дальше, чем окно может ужаться.
      await dragFrom(tester, edgeOf(before, right: 2), const Offset(-5000, 0));

      final after = window(tester);
      expect(after.width, greaterThan(0));
      expect(after.width, lessThan(before.width));
    });

    testWidgets('шире рабочей области окно не растягивается', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, right: 2), const Offset(5000, 0));

      expect(window(tester).width, lessThanOrEqualTo(1200));
    });
  });

  group('память', () {
    /// Точка в полосе заголовка, за которую окно двигают.
    ///
    /// Ниже ручки растяжения: по верхнему краю окна лежит она, и протяжка от
    /// самого края меняла бы размер, а не двигала.
    Offset titleOf(Rect box) => Offset(box.center.dx, box.top + 15);

    /// Закрыть окно: Esc — то же, чем его закрывает человек.
    Future<void> close(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DialogFrame), findsNothing, reason: 'окно не закрылось');
    }

    testWidgets('закрыли и открыли — размер тот же', (tester) async {
      await start(tester);
      await openHelp(tester);
      await dragFrom(tester, edgeOf(window(tester), right: 2), const Offset(150, 0));
      final stretched = window(tester).size;

      await close(tester);
      await openHelp(tester);

      expect(window(tester).width, moreOrLessEquals(stretched.width, epsilon: 2));
    });

    testWidgets('размер уходит в настройки и переживает перезапуск', (tester) async {
      await start(tester);
      await openHelp(tester);
      await dragFrom(tester, edgeOf(window(tester), right: 2), const Offset(150, 0));
      final stretched = window(tester).size;
      await close(tester);

      final saved = runtime.app.dialogState(HelpCommand.commandId);
      expect(saved, isNotNull, reason: 'окно себя не запомнило');
      expect(saved!.width, moreOrLessEquals(stretched.width, epsilon: 2));

      // Новое приложение из тех же настроек — то же окно того же размера.
      runtime = await build(
        settings: AppSettings(
          left: PanelSettings.defaults('/home'),
          right: PanelSettings.defaults('/home'),
          dialogs: {HelpCommand.commandId: DialogState(width: saved.width, height: saved.height)},
        ),
      );
      await start(tester);
      await openHelp(tester);

      expect(window(tester).width, moreOrLessEquals(stretched.width, epsilon: 2));
    });

    testWidgets('закрыли и открыли — окно на том же месте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      // Отодвинули за полосу заголовка — тем же, чем двигает человек.
      await dragFrom(tester, titleOf(before), const Offset(-60, 40));
      final moved = window(tester);
      expect(moved.left, isNot(moreOrLessEquals(before.left, epsilon: 2)), reason: 'окно не поехало');

      await close(tester);
      await openHelp(tester);

      expect(window(tester).left, moreOrLessEquals(moved.left, epsilon: 2));
      expect(window(tester).top, moreOrLessEquals(moved.top, epsilon: 2));
    });

    testWidgets('растянутое вверх окно открывается там же, а не низом к краю', (tester) async {
      // Та самая беда: окно тянут за верхний край, оно уезжает вверх — а
      // открывалось прежней высоты, но от верхнего отступа вниз, и низ
      // упирался в край экрана.
      await start(tester);
      await openHelp(tester);

      await dragFrom(tester, edgeOf(window(tester), top: 2), const Offset(0, -90));
      final stretched = window(tester);

      await close(tester);
      await openHelp(tester);

      expect(window(tester).top, moreOrLessEquals(stretched.top, epsilon: 2));
      expect(window(tester).bottom, moreOrLessEquals(stretched.bottom, epsilon: 2));
    });

    testWidgets('место уходит в настройки и переживает перезапуск', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, titleOf(before), const Offset(-70, 50));
      final moved = window(tester);
      await close(tester);

      final saved = runtime.app.dialogState(HelpCommand.commandId);
      expect(saved, isNotNull, reason: 'окно себя не запомнило');
      expect(saved!.offsetX, moreOrLessEquals(-70, epsilon: 2));
      expect(saved.offsetY, moreOrLessEquals(50, epsilon: 2));

      // Новое приложение из тех же настроек — то же окно на том же месте.
      runtime = await build(
        settings: AppSettings(
          left: PanelSettings.defaults('/home'),
          right: PanelSettings.defaults('/home'),
          dialogs: {
            HelpCommand.commandId: DialogState(
              width: saved.width,
              height: saved.height,
              offsetX: saved.offsetX,
              offsetY: saved.offsetY,
            ),
          },
        ),
      );
      await start(tester);
      await openHelp(tester);

      expect(window(tester).left, moreOrLessEquals(moved.left, epsilon: 2));
      expect(window(tester).top, moreOrLessEquals(moved.top, epsilon: 2));
    });

    testWidgets('двойной щелчок по краю возвращает и место', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, titleOf(before), const Offset(-60, 40));
      expect(window(tester).left, isNot(moreOrLessEquals(before.left, epsilon: 2)));

      final at = edgeOf(window(tester), right: 2);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(window(tester).left, moreOrLessEquals(before.left, epsilon: 2));
      expect(window(tester).top, moreOrLessEquals(before.top, epsilon: 2));
    });

    testWidgets('двойной щелчок по краю возвращает размер по умолчанию', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = window(tester);

      await dragFrom(tester, edgeOf(before, right: 2), const Offset(150, 0));
      expect(window(tester).width, isNot(moreOrLessEquals(before.width, epsilon: 2)));

      final at = edgeOf(window(tester), right: 2);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(window(tester).width, moreOrLessEquals(before.width, epsilon: 2));
      expect(runtime.app.dialogState(HelpCommand.commandId), isNull, reason: 'запомненное не стёрли');
    });
  });

  group('курсор', () {
    /// Курсор, который окажется под указателем в этой точке.
    ///
    /// Ручки лежат поверх окна, и перечисляются они сверху дерева вниз —
    /// значит последний подходящий и есть верхний.
    MouseCursor cursorAt(WidgetTester tester, Offset at) {
      MouseCursor found = MouseCursor.defer;
      for (final region in tester.widgetList<MouseRegion>(find.byType(MouseRegion))) {
        if (region.cursor == MouseCursor.defer) {
          continue;
        }
        final box = tester.renderObject<RenderBox>(find.byWidget(region));
        if (!box.hasSize) {
          continue;
        }
        if ((box.localToGlobal(Offset.zero) & box.size).contains(at)) {
          found = region.cursor;
        }
      }
      return found;
    }

    testWidgets('края показывают, в какую сторону тянуть', (tester) async {
      await start(tester);
      await openHelp(tester);
      final box = window(tester);

      expect(cursorAt(tester, edgeOf(box, right: 2)), SystemMouseCursors.resizeLeftRight);
      expect(cursorAt(tester, edgeOf(box, left: 2)), SystemMouseCursors.resizeLeftRight);
      expect(cursorAt(tester, edgeOf(box, bottom: 2)), SystemMouseCursors.resizeUpDown);
      expect(cursorAt(tester, edgeOf(box, top: 2)), SystemMouseCursors.resizeUpDown);
    });

    testWidgets('на углу есть курсор, а не стрелка', (tester) async {
      // Диагонали на углу нет ни на одной системе, и это наше решение, а не
      // ограничение: Flutter `resizeUpLeftDownRight` наружу не отдаёт нигде,
      // и запрос на него превращается в обычную стрелку — угол выглядел бы
      // так, будто за него не тянут. Достать диагональ можно только своим
      // родным кодом, и держать эту подпорку мы не стали
      // (`docs/spec/dialog-resize.md`, §5).
      await start(tester);
      await openHelp(tester);
      final box = window(tester);

      for (final at in [
        edgeOf(box, left: 2, top: 2),
        edgeOf(box, right: 2, top: 2),
        edgeOf(box, left: 2, bottom: 2),
        edgeOf(box, right: 2, bottom: 2),
      ]) {
        expect(cursorAt(tester, at), SystemMouseCursors.resizeLeftRight, reason: 'угол $at');
      }
    });

    testWidgets('в угол можно попасть: он крупнее полосы края', (tester) async {
      await start(tester);
      await openHelp(tester);
      final box = window(tester);

      // Вдвое дальше от края, чем полоса стороны, — это ещё угол.
      expect(cursorAt(tester, box.bottomRight - const Offset(9, 9)), isNot(MouseCursor.defer));
    });
  });

  group('растянутое окно', () {
    /// Содержимое справки — таблица со всеми командами.
    Rect content(WidgetTester tester) => tester.getRect(find.byType(FcKeyValueSections));

    /// Кнопка, которой окно закрывают: она и есть ряд кнопок справки.
    Rect closeButton(WidgetTester tester) => tester.getRect(find.widgetWithText(FcButton, 'Close'));

    testWidgets('прибавка достаётся содержимому, а не пустоте', (tester) async {
      await start(tester);
      await openHelp(tester);
      final before = content(tester);

      await dragFrom(tester, edgeOf(window(tester), bottom: 2), const Offset(0, 100));

      expect(content(tester).height - before.height, moreOrLessEquals(100, epsilon: 2));
    });

    testWidgets('ряд кнопок прижат к низу окна — и до протяжки, и после', (tester) async {
      await start(tester);
      await openHelp(tester);
      final padding = metrics(tester).dialogPadding;

      expect(closeButton(tester).bottom, moreOrLessEquals(window(tester).bottom - padding, epsilon: 1));

      await dragFrom(tester, edgeOf(window(tester), bottom: 2), const Offset(0, 120));

      expect(closeButton(tester).bottom, moreOrLessEquals(window(tester).bottom - padding, epsilon: 1));
    });

    testWidgets('сжатое до предела окно кнопок не теряет', (tester) async {
      await start(tester);
      await openHelp(tester);

      await dragFrom(tester, edgeOf(window(tester), bottom: 2), const Offset(0, -5000));

      expect(tester.takeException(), isNull);
      expect(closeButton(tester), isNotNull);
      expect(
        closeButton(tester).bottom,
        moreOrLessEquals(window(tester).bottom - metrics(tester).dialogPadding, epsilon: 1),
      );
    });
  });

  group('чего не объявили, того и нет', () {
    testWidgets('окно без resizable ручек не имеет', (tester) async {
      // Окно ошибки тянуться не просило: там две строки и кнопка.
      await start(tester);
      runtime.app.errors.report(const FsError('/home/нет', FsErrorKind.notFound));
      await tester.pumpAndSettle();

      final before = window(tester);
      await dragFrom(tester, edgeOf(before, right: 2), const Offset(150, 0));

      expect(window(tester).width, moreOrLessEquals(before.width, epsilon: 2));
    });
  });
}
