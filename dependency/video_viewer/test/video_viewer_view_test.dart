import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_video_viewer/fc_video_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

/// Вид ролика (`docs/spec/video-viewer.md`, §6–7): кадр текстурой, плашка как
/// у QuickTime, клавиши внутри показа.
void main() {
  late FakeVideoPlayer player;
  late VideoViewerScreen screen;

  Future<void> pump(WidgetTester tester, {bool autoplay = false}) async {
    player = FakeVideoPlayer(42);
    screen = VideoViewerScreen(
      entry: const FileEntry(name: 'clip.mp4', kind: EntryKind.file, path: '/home/clip.mp4', size: 1000),
      player: player,
      source: VideoSource.local('/home/clip.mp4'),
      settings: VideoViewerSettings(),
      onSettingsChanged: () {},
      autoplay: autoplay,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: SizedBox(width: 800, height: 500, child: VideoViewerView(screen: screen))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('кадр — текстурой плеера, по пропорции ролика', (tester) async {
    await pump(tester);

    final texture = tester.widget<Texture>(find.byType(Texture));
    expect(texture.textureId, 42);
    final rect = tester.getRect(find.byType(Texture));
    expect(rect.width / rect.height, closeTo(16 / 9, 0.01));

    // Показ держит таймеры опроса и плашки — закрыть до проверки, что их нет.
    screen.close();
  });

  testWidgets('Space, стрелки и M делают своё', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.calls.last, 'play');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.calls.last, 'seek 5000');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(player.calls, contains('step 1'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(player.calls.last, 'volume 0.9');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(player.calls.last, 'muted true');

    // Показ держит таймеры опроса и плашки — закрыть до проверки, что их нет.
    screen.close();
  });

  testWidgets('пока играет, плашка прячется; клавиша возвращает её', (tester) async {
    await pump(tester, autoplay: true);
    expect(screen.playing, isTrue);
    expect(screen.controlsVisible, isTrue);

    await tester.pump(VideoViewerScreen.hideAfter + const Duration(milliseconds: 100));
    expect(screen.controlsVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(screen.controlsVisible, isTrue);

    // На паузе — видна всегда.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(VideoViewerScreen.hideAfter * 2);
    expect(screen.playing, isFalse);
    expect(screen.controlsVisible, isTrue);

    // Показ держит таймеры опроса и плашки — закрыть до проверки, что их нет.
    screen.close();
  });

  testWidgets('щелчок по полосе перемотки переносит туда', (tester) async {
    await pump(tester);

    final bar = tester.getRect(find.byKey(const ValueKey('video.scrub')));
    await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
    await tester.pump();

    expect(player.calls.last, 'seek 30000', reason: 'середина минутного ролика');

    // Показ держит таймеры опроса и плашки — закрыть до проверки, что их нет.
    screen.close();
  });

  test('время — как на плашке QuickTime', () {
    expect(formatClock(const Duration(seconds: 12)), '0:12');
    expect(formatClock(const Duration(minutes: 3, seconds: 45)), '3:45');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
