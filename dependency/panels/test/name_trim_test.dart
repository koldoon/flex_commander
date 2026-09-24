import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
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
  for (final view in [BriefView.viewId, TreeView.viewId, IconsView.viewId, ColumnsView.viewId]) {
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
}
