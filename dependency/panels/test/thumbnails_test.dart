import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Миниатюра вместо значка формата (`docs/spec/file-thumbnails.md`).
///
/// Через приложение целиком: миниатюра идёт от настроек через службу правил к
/// плитке, и сломаться может любое из звеньев.
void main() {
  /// Красный пиксель: настоящий `png`, который декодер примет.
  final png = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, //
    83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, 0, 3, 1, 1, 0, 201, 254, 146, 239, 0, 0, //
    0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  late _FakeThumbnails system;

  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.file('/home/shot.jpg', size: 100),
    FakeEntry.file('/home/notes.txt', size: 10),
  ])..home = '/home';

  Future<void> open(WidgetTester tester, {String view = IconsView.viewId}) async {
    system = _FakeThumbnails(png);
    final runtime = await testApp(provider: provider(), modules: [...featureModules(), _FakeThumbnailsModule(system)]);
    await runtime.app.start();

    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(view);
    await tester.pumpAndSettle();
  }

  /// Плитка с этим именем — и картинка в ней, если она там есть.
  Finder pictureOf(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(IconTile)).first,
    matching: find.byType(Image),
  );

  testWidgets('в плитке появляется содержимое файла', (tester) async {
    await open(tester);

    expect(system.asked, isNotEmpty, reason: 'сетка просит значок крупным — миниатюру спрашивают');
    expect(pictureOf('shot.jpg'), findsOneWidget);
  });

  testWidgets('миниатюра кроется маской со скруглением', (tester) async {
    await open(tester);

    final clip = find.ancestor(of: pictureOf('shot.jpg'), matching: find.byType(ClipRRect)).first;
    expect(
      tester.widget<ClipRRect>(clip).borderRadius,
      BorderRadius.circular(const DefaultMetrics().panelRadius),
      reason: 'прямой угол рядом со скруглёнными плашками читается чужим',
    );

    // Маска надета на саму картинку, а не на отведённый ей квадрат: широкий
    // снимок не достаёт до верха и низа, и скруглять пустое место незачем.
    expect(tester.getRect(clip), tester.getRect(pictureOf('shot.jpg')));
  });

  testWidgets('миниатюры нет — плитка остаётся со значком', (tester) async {
    await open(tester);

    expect(pictureOf('notes.txt'), findsNothing, reason: 'система сказала «нет», и это ответ');
  });

  testWidgets('в таблице миниатюр не спрашивают вовсе', (tester) async {
    // Значок в строке — 13 точек: миниатюру в нём не разглядеть, и порог её
    // туда не пускает (`docs/spec/file-thumbnails.md`, §6).
    await open(tester, view: PanelSettings.defaultView);

    expect(find.byType(FileTableRow), findsWidgets, reason: 'строки нарисованы');
    expect(system.asked, isEmpty);
  });
}

/// Система, которая умеет показать снимок и не умеет — текст.
class _FakeThumbnails implements SystemThumbnails {
  _FakeThumbnails(this.png);

  final Uint8List png;
  final List<String> asked = [];

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) async {
    asked.add('$path@$pixels');
    return path.endsWith('.jpg') ? png : null;
  }
}

/// Модуль-подставка: в прогоне канала раннера нет, и спрашивать некого.
class _FakeThumbnailsModule implements FcFrontendModule {
  const _FakeThumbnailsModule(this.thumbnails);

  final SystemThumbnails thumbnails;

  @override
  String get id => 'test.thumbnails';

  @override
  String get title => 'Test thumbnails';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<SystemThumbnails>((services) => thumbnails);
  }
}
