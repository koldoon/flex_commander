import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'video_viewer_settings.dart';

/// Показ, который играет: видео или звук.
///
/// Общее у них — то, что делают команды в ряду функциональных клавиш: пуск и
/// пауза, звук, сведения. Команды одни на оба показа, а не по копии на каждый
/// (`docs/spec/audio-viewer.md`, §4).
abstract interface class MediaScreen implements ViewerContent {
  bool get playing;

  /// Громкость и «без звука» — общие у видео и звука.
  VideoViewerSettings get settings;

  Future<void> togglePlay();

  Future<void> toggleMute();

  /// Сведения для окна `Cmd-I`.
  FcTableSection infoSection(Strings strings);
}
