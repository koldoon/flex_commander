import 'dart:typed_data';

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
      // Заголовок `HEIC`: `ftyp` на пятом байте и марка формата за ним. Дальше
      // — мусор, и это нарочно: Flutter такого всё равно не разберёт, а
      // система в прогоне подставная.
      FakeEntry.file('/home/photo.heic', content: [0, 0, 0, 24, ...'ftypheic'.codeUnits, ...'мусор'.codeUnits]),
    ]);
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath().run(path))!;

  Future<ImageDocument> read(String name, {ImageViewerSettings? settings, SystemImages? system}) async =>
      ImageDocument.read(
        entryValueOf(await nodeAt('/home/$name')),
        NodeContent(await nodeAt('/home/$name')),
        settings ?? ImageViewerSettings(),
        checkpoint: () async {},
        system: system,
      );

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

  group('Чего не умеет Flutter', () {
    test('без службы — тот же отказ, что и всегда', () async {
      await expectLater(
        read('photo.heic'),
        throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('Not an image'))),
      );
    });

    test('система разобрала — показываем её картинку, а размеры и формат родные', () async {
      final system = _FakeSystemImages(picture: imageOf(pngData), width: 2860, height: 3814, format: 'HEIC');

      final document = await read('photo.heic', system: system);

      expect(document.width, 2860, reason: 'размеры настоящие, а не от пересжатого');
      expect(document.height, 3814);
      expect(document.format, 'HEIC', reason: 'в плашке должен стоять формат файла, а не то, во что пересжали');
      expect(document.bytes, imageOf(pngData), reason: 'показываем то, что прислала система');
      expect(system.asked, 1);
    });

    test('свой формат систему не спрашивает вовсе', () async {
      final system = _FakeSystemImages(picture: imageOf(pngData), width: 1, height: 1, format: 'HEIC');

      await read('shot.png', system: system);

      expect(system.asked, 0, reason: 'дорога своих форматов не меняется ни на шаг');
    });

    test('точек больше предела — отказ теми же словами', () async {
      // Картинки система не прислала: распаковывать такое она не стала.
      final system = _FakeSystemImages(width: 20000, height: 20000, format: 'HEIC');

      await expectLater(
        read('photo.heic', system: system),
        throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('20000×20000'))),
      );
    });

    test('система тоже не разобрала — отказ, а не пустой экран', () async {
      await expectLater(
        read('photo.heic', system: _FakeSystemImages()),
        throwsA(isA<ViewerRefused>().having((refusal) => refusal.reason, 'reason', contains('Not an image'))),
      );
    });

    test('предел просмотрщика передаётся системе: распаковывать лишнее ей незачем', () async {
      final system = _FakeSystemImages(picture: imageOf(pngData), width: 6, height: 4, format: 'HEIC');
      final settings = ImageViewerSettings()..maxPixels = 1000000;

      await read('photo.heic', settings: settings, system: system);

      expect(system.limit, 1000000);
    });
  });
}

/// Система, отвечающая по команде теста.
class _FakeSystemImages implements SystemImages {
  _FakeSystemImages({this.picture, this.width = 0, this.height = 0, this.format = ''});

  final Uint8List? picture;
  final int width;
  final int height;
  final String format;

  int asked = 0;
  int? limit;

  @override
  Future<SystemImage?> readable(Uint8List bytes, {required int maxPixels}) async {
    asked++;
    limit = maxPixels;
    if (width == 0) {
      return null;
    }
    return SystemImage(width: width, height: height, format: format, bytes: picture);
  }
}
