import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'images.dart';

/// Чтение картинки: размеры и формат — из заголовка, до распаковки.
void main() {
  // Разбор заголовка идёт движком показа, а он живёт в связке с Flutter.
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/shot.png', content: imageOf(pngData)),
      FakeEntry.file('/home/anim.gif', content: imageOf(gifData)),
      FakeEntry.file('/home/dot.bmp', content: imageOf(bmpData)),
      FakeEntry.file('/home/logo.webp', content: imageOf(webpData)),
      FakeEntry.file('/home/notes.png', content: 'это не картинка, а текст'.codeUnits),
    ]);
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath().run(path))!;

  Future<ImageDocument> read(String name, {ImageViewerSettings? settings}) async =>
      ImageDocument.read(await nodeAt('/home/$name'), settings ?? ImageViewerSettings(), checkpoint: () async {});

  test('размеры берутся из заголовка', () async {
    final document = await read('shot.png');

    expect(document.width, 6);
    expect(document.height, 4);
    expect(document.pixels, 24);
  });

  test('формат — по подписи, а не по имени файла', () async {
    // Имя врёт чаще, чем первые байты.
    expect((await read('shot.png')).format, 'PNG');
    expect((await read('anim.gif')).format, 'GIF');
    expect((await read('dot.bmp')).format, 'BMP');
    expect((await read('logo.webp')).format, 'WEBP');
  });

  test('не картинка — отказ словами, а не пустой экран', () async {
    await expectLater(
      read('notes.png'),
      throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('Not an image'))),
    );
  });

  test('слишком большой файл не читается вовсе', () async {
    final settings = ImageViewerSettings(maxFileSize: 10);

    await expectLater(
      read('shot.png', settings: settings),
      throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('too large'))),
    );
  });

  test('слишком много точек — отказ до распаковки', () async {
    // Предел в байтах о памяти ничего не говорит: сжатую картинку распаковка
    // разворачивает в четыре байта на точку.
    final settings = ImageViewerSettings(maxPixels: 10);

    await expectLater(
      read('shot.png', settings: settings),
      throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('6×4'))),
    );
  });

  test('в отказе назван выход: системный просмотр', () async {
    await expectLater(
      read('notes.png'),
      throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('Cmd-O'))),
    );
  });
}
