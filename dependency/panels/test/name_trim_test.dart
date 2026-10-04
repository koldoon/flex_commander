import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Чем жертвовать в длинном имени (`docs/spec/name-trim.md`).
void main() {
  const long = 'невероятно длинное имя файла, которому не хватит никакой ширины.txt';

  /// В колонке имени расширения нет — его показывает соседняя `Ext`.
  const shown = 'невероятно длинное имя файла, которому не хватит никакой ширины';

  InMemoryTreeProvider provider() =>
      InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/$long', size: 10)])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {String? view}) async {
    final runtime = await testApp(provider: provider(), modules: featureModules());
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    if (view != null) {
      await runtime.app.left.setView(view);
      await tester.pumpAndSettle();
    }
    return runtime;
  }

  PanelsSettings settingsOf(AppRuntime runtime) => runtime.app.moduleSettings('fc.panels').section(PanelsSettings.new);

  /// Показанное имя — то, что и правда набрано на экране.
  String nameOnScreen(WidgetTester tester) {
    final texts = tester.widgetList<Text>(find.byType(Text));
    return texts.map((text) => text.data ?? '').firstWhere((text) => text.startsWith('невер'), orElse: () => '');
  }

  testWidgets('по умолчанию режется хвост', (tester) async {
    await open(tester);

    // Многоточие ставит `TextOverflow.ellipsis`, поэтому в самом тексте его
    // нет: набрано имя целиком, а обрезал его показ.
    expect(nameOnScreen(tester), shown);

    await disposeScreen(tester);
  });

  /// Правило одно на все виды: одно и то же имя, выглядящее в дереве и в
  /// таблице по-разному, — это не настройка, а поломка (§3).
  for (final view in [
    BriefView.viewId,
    TreeView.viewId,
    CompactTreeView.viewId,
    IconsView.viewId,
    ColumnsView.viewId,
  ]) {
    testWidgets('середина режется и в виде «$view»', (tester) async {
      final runtime = await open(tester);
      settingsOf(runtime).nameTrim = PanelsSettings.trimMiddle;
      await runtime.app.left.setView(view);
      await tester.pumpAndSettle();

      final name = nameOnScreen(tester);
      expect(name, contains('…'));
      // В дереве и сетке расширение входит в имя, в кратком виде — нет.
      expect(name, anyOf(endsWith('ширины'), endsWith('.txt')));

      await disposeScreen(tester);
    });
  }

  testWidgets('выбрали середину — видны оба конца имени', (tester) async {
    final runtime = await open(tester);

    // Правка в окне настроек видна **сразу**: ждать, пока панель проснётся по
    // другому поводу, значит показывать, что нажатие ни к чему не привело.
    settingsOf(runtime).nameTrim = PanelsSettings.trimMiddle;
    await tester.pumpAndSettle();

    final name = nameOnScreen(tester);
    expect(name, isNot(shown), reason: 'настройка меняет показанное сразу, а не когда-нибудь потом');
    expect(name, startsWith('невер'));
    expect(name, endsWith('ширины'), reason: 'ради хвоста всё и затевалось');
    expect(name, contains('…'));

    await disposeScreen(tester);
  });

  /// Найдено на живом: в сетке значков от имени без пробелов оставалось одно
  /// многоточие на второй строке. Плашку под именем мерили по имени целиком, а
  /// набирали в неё обрезанное серединой — оно переносится по-другому, вторая
  /// строка не влезала и срезалась.
  testWidgets('в сетке обрезанное серединой имя видно целиком', (tester) async {
    // Подобрано под Ahem: в две строки, и вторая у необрезанного короче.
    const solid = 'yosemit yyyyyy.png';
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/$solid', size: 10)])
        ..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    settingsOf(runtime).nameTrim = PanelsSettings.trimMiddle;
    await runtime.app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();

    // Обе панели смотрят в один каталог — берётся сетка левой.
    final name = find.byWidgetPredicate((widget) => widget is Text && (widget.data ?? '').startsWith('yosemit')).first;
    final shown = tester.widget<Text>(name).data!;
    expect(shown, contains('…'));
    expect(shown, endsWith('.png'), reason: 'ради хвоста серединой и режут');

    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: name, matching: find.byType(RichText)));
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'обрезанное имя должно влезть в свои строки целиком');

    // И коробка под имя не уже его самой длинной строки — ровно это и ломалось:
    // её мерили по необрезанному имени, у которого последняя строка короче.
    final box = tester.getSize(find.ancestor(of: name, matching: find.byType(SizedBox)).first);
    final widest = paragraph
        .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: shown.length))
        .fold<double>(0, (width, line) => width > line.right ? width : line.right);
    expect(box.width + 0.01, greaterThanOrEqualTo(widest));

    await disposeScreen(tester);
  });
}
