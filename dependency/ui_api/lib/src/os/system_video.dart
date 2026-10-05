import 'dart:ui';

/// Проигрывание видео силами системы.
///
/// Плеер живёт **там**, где играет, — у Dart только ручка на него и номер
/// текстуры, в которую раннер кладёт кадры (`docs/spec/video-viewer.md`, §3).
///
/// Службы нет — просмотрщик отказывает словами и предлагает открыть файл
/// системой.
abstract interface class SystemVideo {
  /// Открыть ролик по пути на диске.
  ///
  /// **Путём, а не байтами**, в отличие от PDF: ролик бывает в гигабайтах, и
  /// держать его в памяти ради канала нельзя. null — канала нет.
  Future<SystemVideoOpened?> open(String path);
}

/// Что вышло из открытия: плеер или отказ системы словами.
sealed class SystemVideoOpened {
  const SystemVideoOpened();
}

/// Система ролик не играет — и вот почему.
final class SystemVideoRefused extends SystemVideoOpened {
  const SystemVideoRefused(this.reason);

  /// Почему: [unplayable] или [noVideo] — их переводит просмотрщик; прочее —
  /// как сказала система.
  final String reason;

  /// Формат системе не по силам.
  static const String unplayable = 'unplayable';

  /// Видеодорожки нет: в контейнере только звук.
  static const String noVideo = 'noVideo';
}

/// Открытый ролик — ручка на плеер.
abstract interface class SystemVideoPlayer implements SystemVideoOpened {
  /// Текстура, в которую идут кадры, — для виджета `Texture`.
  int get textureId;

  /// Размер кадра в пикселях, уже с учётом поворота (снятое телефоном стоя).
  Size get size;

  /// На сколько четвертей оборота по часовой повернуть кадр текстуры.
  ///
  /// Кадры приходят такими, какими записаны, а поворот лежит в ролике
  /// отдельно: снятое телефоном стоя записано лёжа.
  int get quarterTurns;

  Duration get duration;

  /// Что известно о ролике — для окна сведений.
  SystemVideoInfo get info;

  Future<void> play();

  Future<void> pause();

  /// Перейти точно в [position]: без допуска, иначе шаг на кадр не работает.
  Future<void> seek(Duration position);

  /// Шаг на [frames] кадров вперёд (меньше нуля — назад); плеер встаёт на паузу.
  ///
  /// Силами системы, а не переходом на `1 / частота`: частота бывает
  /// переменной, и подсчёт промахивался бы мимо кадра.
  Future<void> step(int frames);

  /// Громкость от 0 до 1.
  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  /// Где сейчас плеер. null — плеер уже закрыт.
  Future<SystemVideoState?> state();

  /// Отпустить плеер: звук смолкает, текстура снимается.
  Future<void> close();
}

/// Сведения о ролике.
class SystemVideoInfo {
  const SystemVideoInfo({this.videoCodec = '', this.audioCodecs = const [], this.frameRate = 0, this.bitRate = 0});

  /// Кодек видео — как его называет система (`avc1`, `hvc1`).
  final String videoCodec;

  /// Кодеки дорожек звука, по одной строке на дорожку.
  final List<String> audioCodecs;

  /// Кадров в секунду; 0 — неизвестно.
  final double frameRate;

  /// Бит в секунду, по всем дорожкам; 0 — неизвестно.
  final int bitRate;
}

/// Где плеер сейчас.
class SystemVideoState {
  const SystemVideoState({required this.position, required this.playing, required this.ended});

  final Duration position;

  final bool playing;

  /// Доиграл до конца.
  final bool ended;
}
