import 'package:fc_api/fc_api.dart';

/// Что просмотрщик видео помнит между показами (`docs/spec/video-viewer.md`,
/// §9).
class VideoViewerSettings implements Serializable {
  VideoViewerSettings({this.volume = 1, this.muted = false});

  /// Громкость от 0 до 1.
  double volume;

  /// Без звука.
  bool muted;

  @override
  void fromMap(Map<String, dynamic> m) {
    volume = (extract<num>(volume, m['volume'])).toDouble().clamp(0.0, 1.0);
    muted = extract(muted, m['muted']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['volume'] = volume;
    m['muted'] = muted;
  }
}
