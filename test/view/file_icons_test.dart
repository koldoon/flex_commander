import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Значки системы, за которыми видно, о чём и сколько раз спрашивали.
class ProbeIcons implements SystemIcons {
  final List<String> asked = [];

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) async {
    asked.add('path:$path');
    return null;
  }

  @override
  Future<Uint8List?> forExtension(String extension, {required int pixels}) async {
    asked.add('ext:$extension');
    return null;
  }

  @override
  Future<Uint8List?> forKind(SystemIconKind kind, {required int pixels}) async {
    asked.add('kind:${kind.name}');
    return null;
  }
}

/// Подставляет [ProbeIcons] вместо канала раннера.
class ProbeIconsModule implements FcFrontendModule {
  const ProbeIconsModule(this.icons);

  final ProbeIcons icons;

  @override
  String get id => 'test.systemIcons';

  @override
  String get title => 'Probe icons';

  @override
  void installFrontend(FrontendRegistry registry) => registry.service<SystemIcons>((services) => icons);
}

/// Иконки строк по правилам — то, что видно на экране.
///
/// Спецификация — `docs/spec/file-icons.md`. Про сам выбор иконки есть тесты
/// службы (`dependency/file_icons`); здесь проверяется, что панель их слушает и
/// что размер иконки двигает разметку списка.
void main() {
  Future<void> open(WidgetTester tester, {int size = 0, List<Map<String, Object?>> rules = const []}) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/src'),
      FakeEntry.file('/home/main.dart', size: 128),
      FakeEntry.file('/home/notes.txt', size: 64),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    settings.modules.scope('fc.icons').section(FileIconSettings.new)
      ..size = size
      ..rules = FileIconRule.listFromJson(rules);

    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Глиф, которым нарисована строка с этим именем.
  int? glyphOf(WidgetTester tester, String name) {
    final row = find.ancestor(of: find.text(name), matching: find.byType(FileTableRow)).first;
    final icons = find.descendant(of: row, matching: find.byType(Icon));
    return icons.evaluate().isEmpty ? null : tester.widget<Icon>(icons.first).icon?.codePoint;
  }

  testWidgets('кэш значков — один на приложение, а не на панель', (tester) async {
    final probe = ProbeIcons();
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/src'),
      FakeEntry.file('/home/main.dart', size: 128),
      FakeEntry.file('/home/notes.txt', size: 64),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    settings.modules.scope('fc.icons').section(FileIconSettings.new).system = true;

    // Настоящий модуль значков заменён подставным: канала раннера в тесте нет.
    final modules = [...featureModules().where((module) => module.id != 'fc.systemIcons'), ProbeIconsModule(probe)];
    final app = (await testApp(provider: provider, modules: modules, settings: settings)).app;
    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    // Сперва убедимся, что панели **обе** нарисованы: иначе тест ниже сойдётся
    // и на одной, ничего не проверив.
    expect(find.text('notes'), findsNWidgets(2), reason: 'нарисована только одна панель');

    // Обе панели показывают один каталог: восемь строк на экране, но вопросов
    // к системе ровно столько, сколько **разных**. Совпади кэш с панелью —
    // спросили бы вдвое больше; спроси каждая строка за себя — вчетверо.
    expect(probe.asked.toSet(), {'path:/', 'path:/home/src', 'ext:dart', 'ext:txt'});
    expect(probe.asked.length, 4, reason: 'один и тот же вопрос задан дважды');
  });

  testWidgets('без правил всё как было: у каталога папка, у файла ничего', (tester) async {
    await open(tester);

    expect(glyphOf(tester, 'src'), 0xf07b);
    expect(glyphOf(tester, 'notes'), isNull);
  });

  testWidgets('правило по маске меняет иконку', (tester) async {
    await open(
      tester,
      rules: [
        {'mask': '*.dart', 'icon': 'glyph:check'},
      ],
    );

    expect(glyphOf(tester, 'main'), 0xf00c);
    // Остальным досталось то же, что и раньше.
    expect(glyphOf(tester, 'src'), 0xf07b);
    expect(glyphOf(tester, 'notes'), isNull);
  });

  testWidgets('первое совпавшее правило выигрывает', (tester) async {
    await open(
      tester,
      rules: [
        {'mask': '*.dart', 'icon': 'glyph:check'},
        {'mask': '*', 'icon': 'glyph:link'},
      ],
    );

    expect(glyphOf(tester, 'main'), 0xf00c);
    expect(glyphOf(tester, 'notes'), 0xf0c1);
  });

  testWidgets('неразобранное правило ничего не ломает', (tester) async {
    await open(
      tester,
      rules: [
        {'mask': '*.dart', 'icon': 'значок'},
        {'mask': '*.dart', 'icon': 'glyph:check'},
      ],
    );

    expect(glyphOf(tester, 'main'), 0xf00c);
  });

  testWidgets('по умолчанию разметка списка прежняя', (tester) async {
    await open(tester);

    const metrics = DefaultMetrics();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.itemExtent, metrics.rowHeight);
    // Ширина колонки — та, что обещает тема. Числом её писать нельзя: величины
    // темы правят руками, и тест обязан ходить за ними, а не спорить с ними.
    // Именно это и было дефектом: колонка не смотрела на метрики вовсе, и
    // `iconGap` можно было крутить сколько угодно.
    expect(tester.widget<SizedBox>(_iconCell(tester)).width, metrics.iconColumnWidth);
  });

  testWidgets('крупная иконка поднимает и строку, и колонку под собой', (tester) async {
    await open(tester, size: 24);

    // И строка, и колонка растут ровно на то, на сколько выросла иконка.
    const metrics = DefaultMetrics();
    final grown = 24 - metrics.iconSize;

    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.itemExtent, metrics.rowHeight + grown);
    expect(tester.widget<SizedBox>(_iconCell(tester)).width, metrics.iconColumnWidth + grown);
  });
}

/// Ячейка иконки первой строки — это `SizedBox` перед ячейкой имени.
Finder _iconCell(WidgetTester tester) {
  final row = find.byType(FileTableRow).first;
  return find.descendant(of: row, matching: find.byType(SizedBox)).first;
}
