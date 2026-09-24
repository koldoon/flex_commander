import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окраска строк по правилам (`docs/spec/file-colors.md`).
void main() {
  final colors = DefaultColors();

  FileEntry file(String name) => FileEntry(name: name, kind: EntryKind.file, path: '/home/$name');

  /// Правила — те же, какими они приходят из файла настроек.
  FileColors painter(List<Object?> rules) => FileColors(rules: FileColorRule.listFromJson(rules));

  group('правила', () {
    test('первое совпавшее выигрывает, а не последнее', () {
      final rules = painter([
        {'mask': '*.log', 'color': 'error'},
        {'mask': '*.log', 'color': 'secondaryText'},
      ]);

      expect(rules.of(file('tail.log'), colors), colors.error);
    });

    test('не совпало — цвета нет вовсе', () {
      expect(
        painter([
          {'mask': '*.log', 'color': 'error'},
        ]).of(file('notes.txt'), colors),
        isNull,
      );
      expect(painter(const []).of(file('notes.txt'), colors), isNull);
    });

    test('цвет числом разбирается, и непрозрачность дописывается сама', () {
      final painted = painter([
        {'mask': '*.bak', 'color': '#8a8a8a'},
      ]).of(file('отчёт.bak'), colors);

      expect(painted, const Color(0xFF8A8A8A), reason: 'без этого «#8a8a8a» вышел бы полностью прозрачным');
    });

    test('роль, которой в теме нет, не красит — и не мешает следующему правилу', () {
      final rules = painter([
        {'mask': '*.log', 'color': 'заборный'},
        {'mask': '*.log', 'color': 'error'},
      ]);

      expect(rules.of(file('tail.log'), colors), colors.error);
    });

    test('правило про содержимое не совпадает, пока тип неизвестен', () {
      // Читать файл ради цвета нельзя: прокрутка каталога на сто тысяч записей
      // начала бы сто тысяч чтений (§2б).
      final rules = painter([
        {'contentGroup': 'image', 'color': 'error'},
      ]);

      expect(rules.of(file('снимок.png'), colors), isNull);
    });
  });

  group('умолчания', () {
    test('битая ссылка красится сразу, из коробки', () {
      final link = FileEntry(name: 'старая', kind: EntryKind.link, path: '/home/старая', broken: true);

      expect(FileColors(rules: PanelsSettings.defaultFileColors).of(link, colors), colors.error);
    });

    test('ключа в файле нет — живём умолчаниями; есть пустой — живём пустым', () {
      final fresh = PanelsSettings()..fromMap({});
      final cleared = PanelsSettings()..fromMap({'fileColors': const []});

      expect(fresh.fileColors, isNotEmpty);
      expect(cleared.fileColors, isEmpty, reason: 'человек стёр правила — спорить с ним нечего');
    });

    test('правила переживают запись на диск', () {
      final settings =
          PanelsSettings()
            ..fileColors = FileColorRule.listFromJson([
              {'mask': '*.bak', 'color': '#8a8a8a'},
            ]);

      final stored = <String, dynamic>{};
      settings.toMap(stored);
      final read = PanelsSettings()..fromMap(stored);

      expect(read.fileColors.single.color, '#8a8a8a');
      expect(read.fileColors.single.when.matches(file('отчёт.bak')), isTrue);
    });
  });

  group('в панели', () {
    late AppRuntime runtime;

    Future<void> open(WidgetTester tester, {List<Object?>? rules}) async {
      runtime = await testApp(
        provider: InMemoryTreeProvider([
          FakeEntry.directory('/home'),
          FakeEntry.file('/home/notes.txt', size: 1),
          FakeEntry.file('/home/.ssh-config', size: 1),
          FakeEntry.file('/home/отчёт.bak', size: 1),
        ])..home = '/home',
        modules: featureModules(),
        // Скрытые показаны: иначе умолчание «скрытое приглушено» нечем
        // проверить.
        settings: AppSettings(
          left: PanelSettings.defaults('/home')..showHidden = true,
          right: PanelSettings.defaults('/home'),
        ),
      );
      if (rules != null) {
        runtime.app.moduleSettings('fc.panels').section(PanelsSettings.new).fileColors = FileColorRule.listFromJson(
          rules,
        );
      }
      await runtime.app.start();

      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();
    }

    /// Каким цветом написано имя в левой панели.
    Color? colorOf(WidgetTester tester, String name) {
      final text = find.descendant(of: find.byType(FileTable).first, matching: find.text(name));
      return tester.widget<Text>(text.first).style?.color;
    }

    testWidgets('без правил список выглядит как прежде', (tester) async {
      await open(tester, rules: const []);

      expect(colorOf(tester, 'notes'), colors.rowText);
      expect(colorOf(tester, '.ssh-config'), colors.rowText);
    });

    testWidgets('скрытые приглушаются правилом, а не умолчанием', (tester) async {
      // Умолчанием — нечем: в нынешних темах вторичный текст того же цвета,
      // что и обычная строка (§3).
      await open(
        tester,
        rules: [
          {'hidden': true, 'color': '#6c7a99'},
        ],
      );

      expect(colorOf(tester, '.ssh-config'), const Color(0xFF6C7A99));
      expect(colorOf(tester, 'notes'), colors.rowText, reason: 'обычный файл красить не за что');
    });

    testWidgets('правило из настроек красит, и под курсором тоже', (tester) async {
      await open(
        tester,
        rules: [
          {'mask': '*.bak', 'color': '#8a8a8a'},
        ],
      );

      expect(colorOf(tester, 'отчёт'), const Color(0xFF8A8A8A));

      runtime.app.left.setCursorToName('отчёт.bak');
      await tester.pumpAndSettle();

      // «Под курсором всё белое» стирало бы признак ровно тогда, когда на файл
      // смотрят (§2).
      expect(colorOf(tester, 'отчёт'), const Color(0xFF8A8A8A));
    });

    testWidgets('«..» не красится ничем: это выход наверх, а не файл', (tester) async {
      // Имя у него чужое: правило про скрытое совпало бы на нём всегда — точка
      // в начале.
      await open(
        tester,
        rules: [
          {'hidden': true, 'color': '#6c7a99'},
        ],
      );

      expect(colorOf(tester, '..'), isNot(const Color(0xFF6C7A99)));
    });

    testWidgets('пометка цвет не меняет: она показана фоном и полосой', (tester) async {
      await open(
        tester,
        rules: [
          {'mask': '*.bak', 'color': '#8a8a8a'},
        ],
      );

      runtime.app.left.setMarks({'/home/отчёт.bak'}, by: MarkChange.person);
      await tester.pumpAndSettle();

      expect(colorOf(tester, 'отчёт'), const Color(0xFF8A8A8A));
    });
  });
}
