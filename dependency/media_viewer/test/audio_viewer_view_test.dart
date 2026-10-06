import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_media_viewer/fc_media_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

/// Вид звукового файла (`docs/spec/audio-viewer.md`, §1, §4): теги по центру,
/// без обложки — нота, плашка не прячется, `PgDn` — следующий трек.
void main() {
  const one = FileEntry(name: '01.mp3', kind: EntryKind.file, path: '/m/01.mp3', size: 10);
  const two = FileEntry(name: '02.mp3', kind: EntryKind.file, path: '/m/02.mp3', size: 10);

  late FakeSystemVideo system;
  late AudioViewerScreen screen;

  Future<void> pump(WidgetTester tester, SystemAudioTags tags) async {
    system = FakeSystemVideo();
    screen = AudioViewerScreen(
      entry: one,
      player: FakeAudioPlayer('/m/01.mp3', tags),
      source: MediaSource.local('/m/01.mp3'),
      settings: VideoViewerSettings(),
      onSettingsChanged: () {},
      system: system,
      tracks: const [one, two],
      contentOf: (_) => throw UnimplementedError(),
      localPathOf: (entry) => entry.path,
      autoplay: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: SizedBox(width: 800, height: 500, child: AudioViewerView(screen: screen))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('теги по центру, без обложки — нота', (tester) async {
    await pump(tester, const SystemAudioTags(title: 'Song', artist: 'Band', album: 'Record', year: '2019'));

    expect(find.text('Song'), findsOneWidget);
    expect(find.text('Band — Record'), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
    expect(find.byIcon(const DefaultIcons().music), findsOneWidget);
    expect(find.byType(MediaControls), findsOneWidget);

    screen.close();
  });

  testWidgets('обложка декодируется в наибольшем размере показа, а не целиком', (tester) async {
    // PNG 1×1.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await pump(tester, SystemAudioTags(title: 'Song', artwork: png));

    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    final resized = image as ResizeImage;
    final pixels = (360 * tester.view.devicePixelRatio).round();
    expect(resized.width, pixels);
    expect(resized.height, pixels);
    expect(resized.policy, ResizeImagePolicy.fit);

    screen.close();
  });

  testWidgets('сдвиг позиции будит плашку, а не весь вид (§7.5)', (tester) async {
    await pump(tester, const SystemAudioTags());
    var notified = 0;
    screen.addListener(() => notified++);

    (screen.player as FakeAudioPlayer).position = const Duration(seconds: 7);
    await tester.pump(AudioViewerScreen.pollEvery * 2);
    await tester.pump();

    expect(find.text('0:07'), findsOneWidget, reason: 'время на плашке идёт');
    expect(notified, 0, reason: 'обложка, теги и спектр не перестраиваются');

    screen.close();
  });

  testWidgets('без тегов — имя файла', (tester) async {
    await pump(tester, const SystemAudioTags());

    expect(find.text('01.mp3'), findsOneWidget);

    screen.close();
  });

  testWidgets('PgDn — следующий трек', (tester) async {
    await pump(tester, const SystemAudioTags());

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.pump();

    expect(screen.entry.name, '02.mp3');
    expect(system.paths.single.$1, '/m/02.mp3');

    screen.close();
  });
}
