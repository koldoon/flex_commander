/// Соотношение сторон кадра (`docs/spec/video-viewer.md`, §6б).
class VideoAspect {
  const VideoAspect(this.label, this.ratio);

  /// Подпись в окне: `16:9`. У [original] — ключ перевода.
  final String label;

  /// Ширина к высоте; null — как записано в ролике.
  final double? ratio;

  static const VideoAspect original = VideoAspect('Original', null);

  /// Что предлагает окно: от узкого к широкому, вертикальный ролик последним.
  static const List<VideoAspect> all = [
    original,
    VideoAspect('1:1', 1),
    VideoAspect('5:4', 5 / 4),
    VideoAspect('4:3', 4 / 3),
    VideoAspect('3:2', 3 / 2),
    VideoAspect('16:10', 16 / 10),
    VideoAspect('16:9', 16 / 9),
    VideoAspect('1.85:1', 1.85),
    VideoAspect('2.35:1', 2.35),
    VideoAspect('2.39:1', 2.39),
    VideoAspect('9:16', 9 / 16),
  ];
}
