import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эталоны для дизайн-системы: окно и все окна команд — **настоящими шрифтами**.
///
/// Зачем отдельным тестом. Соседние golden нарочно шрифтов не грузят: в
/// widget-тесте по умолчанию стоит Ahem, где каждая буква — квадрат, и снимок
/// получается независимым от того, что установлено на машине. Это верно для
/// проверки **геометрии** — колонок, высот, линеек, — но по нему нельзя сверить
/// набор: кегль, начертание, глифы иконок.
///
/// Макет `docs/design/design.sketch` сверяется с обоими: с соседними — по
/// раскладке, с этими — по набору. Держать их в одном тесте нельзя: соседние
/// обязаны оставаться переносимыми, а эти берут `Consolas` из системы и потому
/// живут только там, где он установлен.
///
/// Обновление: `flutter test --update-goldens test/view/design_anchor_golden_test.dart`.
void main() {
  /// Удалось ли собрать все три набора. Без любого из них снимок сверять не с
  /// чем: подстановка молча заменит шрифт, и расхождение спишут на макет.
  var fontsReady = false;

  setUpAll(() async {
    fontsReady = await _loadFonts();
  });

  /// Приложение с постоянным содержимым: снимки должны отличаться только тем,
  /// какое окно открыто.
  /// [rightPath] — что открыто в правой панели. У окон команд это другой
  /// каталог: окно копирования тем и интересно, что «откуда» и «куда» разные.
  /// У снимка самого окна — тот же, что слева: так на экране видно и курсор, и
  /// пометки, и обе панели с содержимым.
  Future<AppController> openApp(WidgetTester tester, {String rightPath = '/Users/koldoon/Documents'}) async {
    // Провайдер с содержимым, а не обычный: упаковка невыполнима, если приёмник
    // не умеет принимать байты (`canReceive`), и окно упаковки не открылось бы
    // вовсе — а снять его надо тем же путём, каким его открывает человек.
    final provider = InMemoryContentProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Developer'),
      FakeEntry.directory('/Users/koldoon/Developer/bin'),
      FakeEntry.directory('/Users/koldoon/Developer/etc'),
      FakeEntry.directory('/Users/koldoon/Developer/lib'),
      FakeEntry.directory('/Users/koldoon/Developer/manual'),
      FakeEntry.file('/Users/koldoon/Developer/CONTRIBUTORS.xlsx', size: 6144, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/INSTALL', size: 126, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/KEYS', size: 92262, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/LICENSE', size: 15258, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/fetch.xml', size: 11366, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/patch.xml', size: 1946, modified: DateTime(2018, 2, 19)),
      FakeEntry.directory('/Users/koldoon/Documents'),
    ]);

    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon/Developer'),
      right: PanelSettings.defaults(rightPath),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
    return app;
  }

  /// Снимок окна с открытым окном команды.
  ///
  /// Окно открывается **комбинацией**, а не вызовом команды по имени: клавиша,
  /// кнопка нижней панели и строка палитры ведут к одному и тому же
  /// `dispatch`, и снимать надо именно его — тогда снимок не разойдётся с тем,
  /// что увидит человек.
  void anchor(String name, String file, String keys) {
    testWidgets(name, (tester) async {
      if (!fontsReady) {
        markTestSkipped('Шрифты не собрались: Ubuntu, FontAwesome или Consolas недоступны');
        return;
      }

      final app = await openApp(tester);
      app.left.setCursorToName('LICENSE');
      app.left.setMarks({'LICENSE', 'fetch.xml'});
      await tester.pump();

      app.commands.dispatch(KeyCombination.parse(keys));
      await tester.pumpAndSettle();

      await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/$file'));

      await tester.pump(const Duration(milliseconds: 20));
    });
  }

  testWidgets('окно настоящими шрифтами — эталон набора для макета', (tester) async {
    if (!fontsReady) {
      markTestSkipped('Шрифты не собрались: Ubuntu, FontAwesome или Consolas недоступны');
      return;
    }

    final app = await openApp(tester, rightPath: '/Users/koldoon/Developer');
    app.left.setCursorToName('INSTALL');
    app.right.setMarks({'LICENSE', 'fetch.xml'});
    await tester.pump();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/design_anchor.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });

  anchor('окно копирования', 'anchor_copy.png', 'F5');
  anchor('окно переноса', 'anchor_move.png', 'F6');
  anchor('окно упаковки', 'anchor_archive.png', 'Shift-F5');
  anchor('окно поиска', 'anchor_find.png', 'Alt-F7');
  anchor('окно настроек', 'anchor_settings.png', 'F9');
  anchor('окно справки', 'anchor_help.png', 'F1');
  anchor('палитра команд', 'anchor_palette.png', 'Cmd-Shift-P');
}

/// Интерфейсный шрифт и шрифт иконок лежат в ресурсах, шрифт списка — нет.
///
/// `Consolas` в дистрибутив не кладётся (лицензия Microsoft), но у того, кто
/// правит макет, он обычно установлен — и берётся именно он: тема просит его
/// **первым**, и снимок тогда показывает то самое оформление, ради которого
/// шрифт и выбирался.
///
/// Если Consolas не стоит, пробуется запасной `Menlo`, который `DefaultFonts`
/// называет сам. Он системный и лежит коллекцией `.ttc`; `FontLoader` такую
/// принимает не всегда — тогда сверять набор списка нечем, и тест честнее
/// пропустить, чем показать подстановку.
Future<bool> _loadFonts() async {
  const assets = 'assets/fonts';
  final ui = await _load('Ubuntu', ['$assets/Ubuntu-R.ttf', '$assets/Ubuntu-B.ttf']);
  final icons = await _load('FontAwesome', ['$assets/fontawesome-webfont.ttf']);
  // Только Consolas, без подмены. Эталон снят им, и Menlo вместо него — это не
  // «почти то же самое», а другой снимок: на раннере GitHub, где Consolas нет,
  // подмена делала `fontsReady` истинным, тесты шли и падали расхождением в
  // 3–9 %. Нет нужного шрифта — сверять нечем, и снимок пропускается, как и
  // обещано в `spec/design-system.md`.
  final home = Platform.environment['HOME'] ?? '';
  final fixed = await _load('Consolas', ['$home/Library/Fonts/CONSOLA.TTF', '$home/Library/Fonts/CONSOLAB.TTF']);
  return ui && icons && fixed;
}

Future<bool> _load(String family, List<String> paths) async {
  try {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        return false;
      }
      loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
    return true;
  } on Object {
    return false;
  }
}
