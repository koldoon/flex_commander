import 'dart:typed_data';

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_media_viewer/fc_media_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

/// Спектр в просмотре звука (`docs/spec/audio-viewer.md`, §7).
void main() {
  group('движение полос', () {
    const frame = Duration(milliseconds: 16);

    /// Столько хватает, чтобы подъём дошёл до цели.
    const settled = Duration(seconds: 1);

    test('полоса поднимается быстро, но не скачком (§7.8)', () {
      final motion = SpectrumMotion(1)..step(SpectrumMotion.attack, [1]);
      // За постоянную времени — 63% пути: выброс в один кадр не втыкает
      // столбик до верха.
      expect(motion.levels.single, closeTo(0.632, 0.01));

      motion.step(SpectrumMotion.attack * 4, [1]);
      expect(motion.levels.single, closeTo(1, 0.01), reason: 'за пять постоянных — почти до конца');
    });

    test('подъём одинаков на 60 и 120 Гц', () {
      final at60 = SpectrumMotion(1);
      final at120 = SpectrumMotion(1);
      for (var i = 0; i < 6; i++) {
        at60.step(const Duration(microseconds: 16667), [1]);
        at120
          ..step(const Duration(microseconds: 8333), [1])
          ..step(const Duration(microseconds: 8334), [1]);
      }
      expect(at120.levels.single, closeTo(at60.levels.single, 0.001));
    });

    test('доходит до цели и встаёт', () {
      final motion = SpectrumMotion(2)..step(settled, [0.8, 0.2]);

      expect(motion.levels, [0.8, 0.2]);
      expect(motion.peaks, [0.8, 0.2]);
    });

    test('стоят полосы — кадр не нужен (§7.5)', () {
      final motion = SpectrumMotion(2);

      expect(motion.step(settled, [0.5, 0.2]), isTrue);
      expect(motion.step(frame, [0.5, 0.2]), isFalse, reason: 'тот же спектр — рисовать нечего');
      expect(motion.step(frame, [0.6, 0.2]), isTrue);
      expect(SpectrumMotion(1).step(frame, null), isFalse, reason: 'опавший на паузе не рисуется');
    });

    test('опускается плавно: полная высота — за SpectrumMotion.fall', () {
      final motion = SpectrumMotion(1)..step(settled, [1]);

      motion.step(SpectrumMotion.fall ~/ 2, [0]);
      expect(motion.levels.single, closeTo(0.5, 0.01), reason: 'за половину срока — половина высоты');

      motion.step(SpectrumMotion.fall, [0]);
      expect(motion.levels.single, 0);
    });

    test('пик держится, потом падает с ускорением', () {
      final motion = SpectrumMotion(1)..step(settled, [1]);

      motion.step(SpectrumMotion.hold ~/ 2, [0]);
      expect(motion.peaks.single, 1, reason: 'пока держится — стоит наверху');

      // Удержание кончилось — дальше два равных отрезка: во втором пик падает
      // на большее, чем в первом.
      motion.step(SpectrumMotion.hold ~/ 2, [0]);
      final start = motion.peaks.single;
      motion.step(const Duration(milliseconds: 100), [0]);
      final middle = motion.peaks.single;
      motion.step(const Duration(milliseconds: 100), [0]);
      final end = motion.peaks.single;
      expect(start - middle, greaterThan(0), reason: 'после удержания пик падает');
      expect(middle - end, greaterThan(start - middle), reason: 'и всё быстрее');
    });

    test('тишина — всё опадает до нуля, и тогда «в покое»', () {
      final motion = SpectrumMotion(3)..step(frame, [0.5, 0.9, 0.1]);
      expect(motion.resting, isFalse);

      for (var i = 0; i < 200; i++) {
        motion.step(frame, null);
      }

      expect(motion.resting, isTrue);
    });
  });

  group('виджет', () {
    Future<FakeAudioPlayer> pump(WidgetTester tester, {required bool playing, FakeAudioPlayer? player}) async {
      final audio =
          player ?? (FakeAudioPlayer('/m/a.mp3', const SystemAudioTags())..levels = (Float32List(64)..[10] = 0.9));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [
              FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
            ],
          ),
          home: Scaffold(
            body: SizedBox(width: 400, height: 100, child: MediaSpectrum(player: audio, playing: playing)),
          ),
        ),
      );
      return audio;
    }

    testWidgets('на паузе плеер не спрашивают', (tester) async {
      final player = await pump(tester, playing: false);

      await tester.pump(const Duration(milliseconds: 500));

      expect(player.spectrumCalls, 0);
    });

    testWidgets('играет — спрашивает на каждом кадре', (tester) async {
      final player = await pump(tester, playing: true);
      final before = player.spectrumCalls;

      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }

      // Секунда кадров по 8 мс (120 Гц) — 120 запросов: окно у раннера на
      // каждом свое, по часам плеера (`docs/spec/audio-viewer.md`, §7.7).
      expect(player.spectrumCalls - before, 120);

      // Встали — опадает и затихает: тикер не держит кадры.
      await pump(tester, playing: false, player: player);
      await tester.pump(const Duration(seconds: 3));
      final asked = player.spectrumCalls;
      await tester.pump(const Duration(seconds: 1));
      expect(player.spectrumCalls, asked);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'опавший спектр не рисует впустую');
    });

    testWidgets('сменился трек — спрашивают новый плеер', (tester) async {
      final first = await pump(tester, playing: true);
      await tester.pump(const Duration(milliseconds: 100));

      final second = FakeAudioPlayer('/m/b.mp3', const SystemAudioTags())..levels = Float32List(64);
      await pump(tester, playing: true, player: second);
      final before = first.spectrumCalls;
      await tester.pump(const Duration(milliseconds: 200));

      expect(first.spectrumCalls, before);
      expect(second.spectrumCalls, greaterThan(0));

      await pump(tester, playing: false, player: second);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
