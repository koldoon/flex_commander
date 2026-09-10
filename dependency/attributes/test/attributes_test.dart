import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_attributes/fc_attributes.dart';
import 'package:fc_attributes/src/attributes_form.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево, которое умеет атрибуты — и помнит, что с ними сделали.
class _AttributeProvider extends InMemoryTreeProvider implements NodeAttributesEditor, NodeXattrEditor {
  _AttributeProvider(super.entries);

  /// Режим по пути; чего нет — то `644` у файла и `755` у каталога.
  final Map<String, int> modes = {};
  final Map<String, Map<String, List<int>>> xattrs = {};
  final Map<String, DateTime> modified = {};
  final Map<String, DateTime> accessed = {};

  /// Пути, на которых назначение режима отказывает: изображаем чужой объект.
  ///
  /// Своё поле, а не `denied` подставки: та отказывает на чтении каталога, а
  /// нам нужен отказ ровно на правке.
  final Set<String> deniedModes = {};

  /// Что показывает **список**: у подставки он у всех один и тот же
  /// (`rwxrwxrwx`), а нам нужно, чтобы у объектов он расходился.
  final Map<String, int> listedModes = {};

  /// Что назначали — по порядку. По нему видно, кого работа обошла.
  final List<String> touched = [];

  int modeOf(String path) => modes[path] ?? (_isDirectory(path) ? 0x41ED : 0x81A4);

  bool _isDirectory(String path) => path.endsWith('/') || !path.split('/').last.contains('.');

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    final base = super.getDirectoryListing();
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final nodes = await op.delegate(base, params);
      for (final node in nodes) {
        final listed = listedModes[node.pathString];
        if (node is FileNode && listed != null) {
          node.attributes = FileAttributes.fromMode(listed, 'rw-r--r--', node.fileType);
        }
      }
      return nodes;
    });
  }

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async {
    final path = node.pathString;
    final mode = modeOf(path);
    return NodeAttributes(
      mode: mode,
      modeString: '-rw-r--r--',
      uid: 501,
      gid: 20,
      owner: 'tester',
      group: 'staff',
      modified: modified[path] ?? DateTime.utc(2020, 1, 2, 3, 4, 5),
      accessed: accessed[path] ?? DateTime.utc(2020, 1, 2, 3, 4, 6),
      canEditMode: true,
      canEditTimes: true,
      canEditOwner: true,
    );
  }

  @override
  Future<void> setMode(FsNode node, int mode) async {
    final path = node.pathString;
    if (deniedModes.contains(path)) {
      throw FsError(path, FsErrorKind.permissionDenied);
    }
    touched.add(path);
    modes[path] = (modeOf(path) & ~0xFFF) | (mode & 0xFFF);
  }

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async {
    touched.add(node.pathString);
    if (modified != null) {
      this.modified[node.pathString] = modified;
    }
    if (accessed != null) {
      this.accessed[node.pathString] = accessed;
    }
  }

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async {
    // Сменить владельца обычно не дают — и мы не притворяемся.
    throw FsError(node.pathString, FsErrorKind.permissionDenied);
  }

  @override
  Future<List<Xattr>> readXattrs(FsNode node) async => [
    for (final one in (xattrs[node.pathString] ?? const <String, List<int>>{}).entries) Xattr(one.key, one.value),
  ];

  @override
  Future<void> setXattr(FsNode node, String name, List<int> value) async {
    (xattrs[node.pathString] ??= {})[name] = value;
  }

  @override
  Future<void> removeXattr(FsNode node, String name) async {
    xattrs[node.pathString]?.remove(name);
  }
}

/// Дерево без единого умения: архив.
class _PlainProvider extends InMemoryTreeProvider {
  _PlainProvider(super.entries);
}

void main() {
  late _AttributeProvider provider;
  late AppController app;

  Future<void> start(InMemoryTreeProvider tree) async {
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app =
        (await testApp(
          provider: tree,
          modules: [const Navigation(), const AttributeEditing()],
          settings: settings,
        )).app;
  }

  setUp(() async {
    provider = _AttributeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/deep.txt', size: 10),
      FakeEntry.directory('/home/docs/inner'),
      FakeEntry.file('/home/docs/inner/nested.txt', size: 10),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ]);
    await start(provider);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  /// Открыть окно клавишей.
  ///
  /// Здесь второе сочетание, а не `Ctrl-A`: в тестах платформа не macOS, а там
  /// `Cmd-A` разбирается **как** `Ctrl-A` и достаётся пометке «выделить всё».
  /// Ровно ради этого случая второе сочетание и заведено.
  Future<void> pressCtrlA(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  Future<void> putCursorOn(WidgetTester tester, String name) async {
    app.left.setCursorToName(name);
    await settle(tester);
  }

  /// Флажок по подписи — вместе с его нынешним состоянием.
  bool? checkboxValue(WidgetTester tester, String label) =>
      tester.widgetList<FcCheckbox>(find.byType(FcCheckbox)).firstWhere((box) => box.label == label).value;

  /// Поле по подсказке в нём: подписи в форме стоят отдельным столбцом, и
  /// искать поле «под подписью» пришлось бы через раскладку.
  Finder fieldWithHint(String hint) =>
      find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == hint);

  Future<void> tapCheckbox(WidgetTester tester, String label, {int at = 0}) async {
    await tester.tap(find.text(label).at(at));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FcButton, 'Apply'));
    await settle(tester);
  }

  group('окно', () {
    testWidgets('Ctrl-A открывает окно правки', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      await pressCtrlA(tester);

      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Octal'), findsOneWidget);
    });

    testWidgets('ширина окна не зависит от содержимого', (tester) async {
      provider.xattrs['/home/notes.txt'] = {
        'com.apple.metadata:kMDItemWhereFroms': utf8.encode('https://example.com/very/long/path'),
      };
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);
      final wide = tester.getRect(find.byType(DialogWidth)).width;

      // У этого файла расширенных нет вовсе — окно обязано остаться тем же.
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
      await settle(tester);
      await putCursorOn(tester, 'report.txt');
      await pressCtrlA(tester);

      expect(tester.getRect(find.byType(DialogWidth)).width, closeTo(wide, 0.5));
      expect(wide, closeTo(AttributesForm.width, 0.5));
    });

    testWidgets('поля заполнены свежим, а не тем, что приехало со списком', (tester) async {
      // В списке подставное дерево показывает `rwxrwxrwx`, а провайдер о том же
      // объекте говорит `644`: окно обязано показать второе.
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      await pressCtrlA(tester);

      expect(app.left.currentEntry!.attributes.modeString, 'rwxrwxrwx');
      expect(checkboxValue(tester, 'write'), isTrue, reason: 'запись владельцу — из свежих 644');
      expect(checkboxValue(tester, 'exec'), isFalse, reason: 'в списке стояло бы «да»');
    });

    testWidgets('правка флажка меняет восьмеричное поле', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      expect(find.widgetWithText(TextField, '0644'), findsOneWidget);

      // Первый «execute» в окне — владельца.
      await tapCheckbox(tester, 'exec');

      expect(find.widgetWithText(TextField, '0744'), findsOneWidget);
    });

    testWidgets('у нескольких целей расходящийся флажок — смешанный', (tester) async {
      provider.listedModes['/home/notes.txt'] = 0x81A4; // 644
      provider.listedModes['/home/report.txt'] = 0x81ED; // 755
      await pumpApp(tester);
      app.left.setMarks({'/home/notes.txt', '/home/report.txt'});
      await settle(tester);

      await pressCtrlA(tester);

      // Чтение владельцем есть у обоих, запуск — только у одного.
      expect(checkboxValue(tester, 'read'), isTrue);
      expect(checkboxValue(tester, 'exec'), isNull);
      // Дат и владельца у набора не показываем: у пятнадцати файлов это каша.
      expect(find.text('Modified'), findsNothing);
    });

    testWidgets('Apply без единой правки ничего не трогает', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      await apply(tester);

      expect(provider.touched, isEmpty, reason: 'работу заводить было незачем');
      expect(find.text('Apply'), findsNothing, reason: 'окно закрылось');
    });

    testWidgets('правка режима доходит до источника', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      await tapCheckbox(tester, 'exec');
      await apply(tester);

      expect(provider.modeOf('/home/notes.txt') & 0xFFF, 0x1E4);
    });
  });

  group('рекурсия', () {
    testWidgets('выключена — правится только названное', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'docs');
      await pressCtrlA(tester);

      await tapCheckbox(tester, 'exec');
      await apply(tester);

      expect(provider.touched, ['/home/docs']);
    });

    testWidgets('включена — правка идёт по всему дереву', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'docs');
      await pressCtrlA(tester);

      await tapCheckbox(tester, 'Recursive');
      await tapCheckbox(tester, 'write', at: 1);
      await apply(tester);

      expect(provider.touched, contains('/home/docs/deep.txt'));
      expect(provider.touched, contains('/home/docs/inner/nested.txt'));
      expect(provider.touched, contains('/home/docs/inner'));
    });

    testWidgets('«только файлы» каталогов внутри не трогает', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'docs');
      await pressCtrlA(tester);

      await tapCheckbox(tester, 'Recursive');
      await tester.tap(find.text('files and directories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('only files').last);
      await tester.pumpAndSettle();
      await tapCheckbox(tester, 'write', at: 1);
      await apply(tester);

      // Названный каталог правится при любом отборе: его выбрали руками.
      expect(provider.touched, contains('/home/docs'));
      expect(provider.touched, contains('/home/docs/deep.txt'));
      expect(provider.touched, isNot(contains('/home/docs/inner')));
    });

    testWidgets('среди одних файлов флажок погашен', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      final box = tester.widgetList<FcCheckbox>(find.byType(FcCheckbox)).firstWhere((one) => one.label == 'Recursive');
      // Показан, но не трогается: пропадающее поле переставляло бы всё, что под
      // ним, прямо под курсором человека.
      expect(box.onChanged, isNull);
    });
  });

  group('расширенные атрибуты', () {
    testWidgets('видны, добавляются и убираются', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.apple.quarantine': utf8.encode('0083;Safari')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      expect(find.text('com.apple.quarantine'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Remove'));
      await tester.pumpAndSettle();
      await apply(tester);

      expect(provider.xattrs['/home/notes.txt'], isEmpty);
    });

    testWidgets('строка не слипается: между управлениями обычный просвет', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.apple.quarantine': utf8.encode('0083;Safari')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // `dialogGap` — та же мера, которой отбиты друг от друга кнопки окна.
      const gap = 8.0;
      final value = tester.getRect(fieldWithHint('value'));
      final add = tester.getRect(find.widgetWithText(FcButton, 'Add'));
      expect(add.left - value.right, greaterThanOrEqualTo(gap));

      final name = tester.getRect(fieldWithHint('name'));
      expect(value.left - name.right, greaterThanOrEqualTo(gap));
    });

    testWidgets('короткая кнопка встаёт там же, где длинная', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.apple.quarantine': utf8.encode('0083;Safari')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // «Add» короче «Remove», и по левому краю им не сойтись — в образце
      // строка нового атрибута стоит своей раскладкой, без столбца размера.
      // Сходятся они по правому краю: обе кнопки прижаты к краю окна, и
      // столбец кнопок читается прямым.
      final remove = tester.getRect(find.widgetWithText(FcButton, 'Remove'));
      final add = tester.getRect(find.widgetWithText(FcButton, 'Add'));
      expect(add.right, closeTo(remove.right, 0.5));
      expect(add.width, lessThan(remove.width), reason: 'кнопка по-прежнему по своей подписи');

      // И поля значения кончаются на одной вертикали. Меряются одинаковые узлы
      // — сами поля, а не то, что у них внутри.
      Rect fieldAt(String prefix) => tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith(prefix),
        ),
      );

      expect(fieldAt('new-value:').right, lessThan(add.left));
      expect(fieldAt('xattr:').right, lessThan(remove.left));
    });

    testWidgets('длинное имя не встаёт в две строки, а режется многоточием', (tester) async {
      const long = 'com.apple.metadata:kMDItemWhereFroms';
      provider.xattrs['/home/notes.txt'] = {'com.apple.macl': utf8.encode('x'), long: utf8.encode('y')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      final short = tester.getRect(find.text('com.apple.macl'));
      final wide = tester.getRect(find.text(long));

      // Перенос сдвинул бы соседей по строке и разъехал бы таблицу. Ширина у
      // обоих одна: столбец задан долей окна, а не длиной нынешнего имени, —
      // ради этого ширина окна и назначена числом.
      expect(wide.height, closeTo(short.height, 0.5));
      expect(wide.width, closeTo(short.width, 0.5));
      expect(tester.getRect(find.byType(DialogWidth)).width, closeTo(AttributesForm.width, 0.5));
    });

    testWidgets('их десяток не переполняет окно, а прокручивается', (tester) async {
      provider.xattrs['/home/notes.txt'] = {
        for (var i = 0; i < 12; i++) 'com.example.mark$i': utf8.encode('значение $i'),
      };
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Рядов больше, чем помещается в окно 802×621: рама прокручивает
      // содержимое, а не переполняется молча.
      expect(tester.takeException(), isNull);
    });

    testWidgets('длинное имя не съедает столбец значения', (tester) async {
      const long = 'com.apple.metadata:kMDItemWhereFroms';
      provider.xattrs['/home/notes.txt'] = {long: List.filled(72, 7)};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Двоичное показывается счётом байт; ужиматься ему некуда, и в один знак
      // ширины оно вставало бы столбиком по букве.
      final value = tester.getRect(find.text('72 bytes'));
      expect(value.width, greaterThan(40));
      expect(value.height, lessThan(30), reason: 'одна строка, а не столбик');
    });

    testWidgets('видно четыре строки, дальше прокрутка', (tester) async {
      provider.xattrs['/home/notes.txt'] = {
        for (var i = 0; i < 9; i++) 'com.example.mark$i': utf8.encode('значение $i'),
      };
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Ближайшая прокрутка над строкой — своя, списка, а не рамы окна.
      final list = tester.state<ScrollableState>(
        find.ancestor(of: find.text('com.example.mark0'), matching: find.byType(Scrollable)).first,
      );
      final row = tester.getRect(find.byType(Table).last).height / 9;

      // Список ограничен четырьмя строками — у файла с диска их бывает и
      // десяток, а окно расти без предела не должно.
      expect(list.position.viewportDimension, closeTo(row * 4, row));
      expect(list.position.maxScrollExtent, greaterThan(0), reason: 'до остальных листают');
    });

    testWidgets('заголовок и строки начинаются от левого поля', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.example.mark': utf8.encode('x')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Столбец подписей заголовкам разделов не начальник: отодвинутые на его
      // ширину, они выглядели бы приклеенными к форме сбоку.
      final octal = tester.getRect(find.text('Octal')).left;
      expect(tester.getRect(find.text('Extended attributes')).left, closeTo(octal, 0.5));
      expect(tester.getRect(find.text('Apply to')).left, closeTo(octal, 0.5));
      expect(tester.getRect(find.text('com.example.mark')).left, closeTo(octal, 0.5));

      // А поле с подписью — правее: перед ним стоит столбец подписей.
      expect(tester.getRect(fieldWithHint('user')).left, greaterThan(octal));
    });

    testWidgets('строки списка идут тем же шагом, что поля формы', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.example.a': utf8.encode('1'), 'com.example.b': utf8.encode('2')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Меряются одинаковые узлы — сами поля: у текста своя высота, и по нему
      // шаг не сравнить.
      Rect fieldAt(String prefix) => tester.getRect(
        find
            .byWidgetPredicate(
              (widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith(prefix),
            )
            .first,
      );

      // Строки списка и поля окна читаются как один ряд: разный шаг у них
      // разъезжался бы на глазах.
      final inList = fieldAt('xattr:com.example.b').top - fieldAt('xattr:com.example.a').bottom;
      final inForm = fieldAt('Modified:').top - fieldAt('owner:').bottom;

      expect(inList, closeTo(inForm, 0.5));
    });

    testWidgets('заголовок отбит от таблицы, а не приклеен к ней', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.example.a': utf8.encode('1')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // Вплотную заголовок читается как первая строка таблицы.
      final heading = tester.getRect(find.text('Extended attributes'));
      final firstRow = tester.getRect(find.text('com.example.a'));
      expect(firstRow.top - heading.bottom, greaterThanOrEqualTo(8));
    });

    testWidgets('имя ярче счёта байт: смотрят на имя', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.example.mark': List.filled(7, 0)};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      final theme = FcTheme.of(tester.element(find.text('com.example.mark')));
      expect(tester.widget<Text>(find.text('com.example.mark')).style?.color, theme.colors.dialogLabel);
      expect(tester.widget<Text>(find.text('7 bytes')).style?.color, theme.colors.dialogText);
    });

    testWidgets('полное имя — подсказкой', (tester) async {
      const long = 'com.apple.metadata:kMDItemWhereFroms';
      provider.xattrs['/home/notes.txt'] = {long: utf8.encode('https://example.com')};
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      // В столбце имя режется многоточием, а спрашивают о нём именно тогда,
      // когда не влезло.
      final tips = tester.widgetList<Tooltip>(find.byType(Tooltip)).map((one) => one.message).toList();
      expect(tips, contains(long));
      expect(tips, contains('https://example.com'), reason: 'у значения тоже: оно длиннее поля');
    });

    testWidgets('источник без этого умения раздела не показывает', (tester) async {
      // Ровно как сервер по SFTP: обычные атрибуты умеет, расширенных у него
      // нет вовсе.
      await start(_OnlyPlainAttributes([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]));
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      expect(find.text('Octal'), findsOneWidget);
      expect(find.text('Extended attributes'), findsNothing);
    });
  });

  group('отказы', () {
    testWidgets('смена владельца без прав — ошибка, окно не закрылось', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      await tester.enterText(fieldWithHint('user'), '0');
      await tester.pumpAndSettle();
      await apply(tester);

      expect(find.textContaining('Permission denied'), findsOneWidget);
    });

    testWidgets('отказ на одном из нескольких спрашивает, а не рушит всё', (tester) async {
      provider.deniedModes.add('/home/docs/deep.txt');
      await pumpApp(tester);
      await putCursorOn(tester, 'docs');
      await pressCtrlA(tester);

      await tapCheckbox(tester, 'Recursive');
      await tapCheckbox(tester, 'write', at: 1);
      await apply(tester);

      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Skip all'));
      await settle(tester);

      // Остальные дошли: «отменить всё из-за одного» означало бы, что
      // рекурсией пользоваться нельзя.
      expect(provider.touched, contains('/home/docs/inner/nested.txt'));
    });
  });

  group('источник без умений', () {
    testWidgets('команда есть, но окно правки ничего не обещает', (tester) async {
      await start(_PlainProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]));
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');
      await pressCtrlA(tester);

      final boxes = tester.widgetList<FcCheckbox>(find.byType(FcCheckbox)).where((one) => one.label == 'read');
      expect(boxes.every((one) => one.onChanged == null), isTrue);
    });
  });

  group('мимо окна', () {
    testWidgets('параметр recursive делает то же самое', (tester) async {
      await pumpApp(tester);
      await putCursorOn(tester, 'docs');

      // Правка дерева выразима параметром: из палитры, из привязки клавиши, из
      // сценария — окна при этом никто не видит.
      app.commands.run('file.attributes', const CommandInvocation(parameters: {'recursive': true}));
      await settle(tester);
      await tapCheckbox(tester, 'write', at: 1);
      await apply(tester);

      expect(provider.touched, contains('/home/docs/inner/nested.txt'));
    });
  });

  group('кнопка в сведениях', () {
    Future<void> startWith(List<FcModule> modules) async {
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: provider, modules: modules, settings: settings)).app;
    }

    testWidgets('открывает окно правки', (tester) async {
      await startWith([const Navigation(), const FileInfo(), const AttributeEditing()]);
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      app.commands.run('file.info');
      await settle(tester);
      expect(find.text('Edit…'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Edit…'));
      await settle(tester);

      expect(find.text('Apply'), findsOneWidget, reason: 'сведения закрылись, правка открылась');
    });

    testWidgets('без модуля правки кнопки нет вовсе', (tester) async {
      // Правило В3: команды нет — модуль выключен — и обещать нечего.
      await startWith([const Navigation(), const FileInfo()]);
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      app.commands.run('file.info');
      await settle(tester);

      expect(find.text('Edit…'), findsNothing);
      expect(find.text('Calculate'), findsNothing, reason: 'под курсором файл, а не каталог');
    });
  });

  group('раздел в сведениях', () {
    Future<void> startWith(List<FcModule> modules) async {
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: provider, modules: modules, settings: settings)).app;
    }

    testWidgets('расширенные атрибуты видны в окне сведений', (tester) async {
      provider.xattrs['/home/notes.txt'] = {
        'com.apple.quarantine': utf8.encode('0083;Safari'),
        'com.apple.FinderInfo': List.filled(32, 0),
      };
      await startWith([const Navigation(), const FileInfo(), const AttributeEditing()]);
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      app.commands.run('file.info');
      await settle(tester);

      expect(find.text('Extended attributes'), findsOneWidget);
      expect(find.text('com.apple.quarantine'), findsOneWidget);
      expect(find.text('0083;Safari'), findsOneWidget);
      // Двоичное текстом не притворяется и здесь: показать кашу вместо
      // `FinderInfo` хуже, чем сказать, сколько в нём байт.
      expect(find.text('32 bytes'), findsOneWidget);
    });

    testWidgets('нечего сказать — раздела нет вовсе', (tester) async {
      await startWith([const Navigation(), const FileInfo(), const AttributeEditing()]);
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      app.commands.run('file.info');
      await settle(tester);

      // Пустой заголовок — обещание, которого не сдержали.
      expect(find.text('Extended attributes'), findsNothing);
      expect(find.text('General'), findsOneWidget, reason: 'остальные разделы на месте');
    });

    testWidgets('без модуля правки раздела нет, а сведения работают', (tester) async {
      provider.xattrs['/home/notes.txt'] = {'com.apple.quarantine': utf8.encode('0083;Safari')};
      await startWith([const Navigation(), const FileInfo()]);
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      app.commands.run('file.info');
      await settle(tester);

      expect(find.text('Extended attributes'), findsNothing);
      expect(find.text('General'), findsOneWidget);
    });
  });

  group('без модуля', () {
    testWidgets('Ctrl-A ничего не делает, и приложение работает', (tester) async {
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: provider, modules: [const Navigation()], settings: settings)).app;
      await pumpApp(tester);
      await putCursorOn(tester, 'notes.txt');

      await pressCtrlA(tester);

      expect(find.text('Apply'), findsNothing);
      expect(app.left.entries, isNotEmpty);
    });
  });
}

/// Обычные атрибуты умеет, расширенных не знает — как сервер по SFTP.
class _OnlyPlainAttributes extends InMemoryTreeProvider implements NodeAttributesEditor {
  _OnlyPlainAttributes(super.entries);

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async =>
      const NodeAttributes(mode: 0x81A4, modeString: '-rw-r--r--', canEditMode: true);

  @override
  Future<void> setMode(FsNode node, int mode) async {}

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async {}

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async {}
}
