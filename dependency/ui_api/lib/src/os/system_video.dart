import 'dart:typed_data';
import 'dart:ui';

/// Проигрывание видео и звука силами системы.
///
/// Плеер живёт **там**, где играет, — у Dart только ручка на него, а у видео
/// ещё и номер текстуры, в которую раннер кладёт кадры
/// (`docs/spec/video-viewer.md`, §3; `docs/spec/audio-viewer.md`, §2).
///
/// Службы нет — просмотрщик отказывает словами и предлагает открыть файл
/// системой.
abstract interface class SystemVideo {
  /// Открыть ролик по пути на диске.
  ///
  /// **Путём, а не байтами**, в отличие от PDF: ролик бывает в гигабайтах, и
  /// держать его в памяти ради канала нельзя. null — канала нет.
  Future<SystemVideoOpened?> open(String path);

  /// Открыть звуковой файл по пути на диске — тем же плеером, только без
  /// кадров. null — канала нет.
  Future<SystemVideoOpened?> openAudio(String path);
}

/// Что вышло из открытия: плеер или отказ системы словами.
sealed class SystemVideoOpened {
  const SystemVideoOpened();
}

/// Система файл не играет — и вот почему.
final class SystemVideoRefused extends SystemVideoOpened {
  const SystemVideoRefused(this.reason);

  /// Почему: [unplayable], [noVideo] или [noAudio] — их переводит
  /// просмотрщик; прочее — как сказала система.
  final String reason;

  /// Формат системе не по силам.
  static const String unplayable = 'unplayable';

  /// Видеодорожки нет: в контейнере только звук.
  static const String noVideo = 'noVideo';

  /// Звуковой дорожки нет.
  static const String noAudio = 'noAudio';
}

/// Открытый плеер — общее у видео и звука.
abstract interface class SystemMediaPlayer implements SystemVideoOpened {
  Duration get duration;

  /// Что известно о файле — для окна сведений.
  SystemVideoInfo get info;

  Future<void> play();

  Future<void> pause();

  /// Перейти точно в [position]: без допуска, иначе шаг на кадр не работает.
  Future<void> seek(Duration position);

  /// Громкость от 0 до 1.
  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  /// Где плеер — по мере того, как меняется: раннер шлёт сам, раз в четверть
  /// секунды, пока идёт время, и сразу на пуске, остановке, перемотке и конце
  /// (`docs/spec/audio-viewer.md`, §7.5). Закрылся плеер — поток кончается.
  Stream<SystemVideoState> get states;

  /// Где сейчас плеер — разовым вопросом (шаг на кадр). null — плеер уже закрыт.
  Future<SystemVideoState?> state();

  /// Отпустить плеер: звук смолкает, текстура (у видео) снимается.
  Future<void> close();
}

/// Открытый ролик — ручка на плеер и текстура с кадрами.
abstract interface class SystemVideoPlayer implements SystemMediaPlayer {
  /// Текстура, в которую идут кадры, — для виджета `Texture`.
  int get textureId;

  /// Размер кадра в пикселях, уже с учётом поворота (снятое телефоном стоя).
  Size get size;

  /// На сколько четвертей оборота по часовой повернуть кадр текстуры.
  ///
  /// Кадры приходят такими, какими записаны, а поворот лежит в ролике
  /// отдельно: снятое телефоном стоя записано лёжа.
  int get quarterTurns;

  /// Шаг на [frames] кадров вперёд (меньше нуля — назад); плеер встаёт на паузу.
  ///
  /// Силами системы, а не переходом на `1 / частота`: частота бывает
  /// переменной, и подсчёт промахивался бы мимо кадра.
  Future<void> step(int frames);
}

/// Открытый звуковой файл — ручка на плеер и теги.
abstract interface class SystemAudioPlayer implements SystemMediaPlayer {
  /// Теги файла: название, исполнитель, альбом, год, обложка.
  SystemAudioTags get tags;

  /// Спектр того, что звучит сейчас: [spectrumBands] полос по
  /// логарифмической шкале 40 Гц … 16 кГц, каждая 0…1
  /// (`docs/spec/audio-viewer.md`, §7). null — плеер закрыт или спектра нет.
  ///
  /// Синхронно: спрашивают его каждый кадр, и раннер считает его по прямому
  /// вызову, без канала (§7.5).
  Float32List? spectrum();
}

/// Сколько полос в спектре.
const int spectrumBands = 64;

/// Теги звукового файла — то, что о нём знает система (`commonMetadata`).
class SystemAudioTags {
  const SystemAudioTags({this.title = '', this.artist = '', this.album = '', this.year = '', this.artwork});

  final String title;
  final String artist;
  final String album;

  /// Год строкой: так он и лежит в тегах (`2019`, `2019-05-03`).
  final String year;

  /// Обложка — байтами картинки (`jpeg`, `png`); null — её нет.
  final Uint8List? artwork;

  /// Тегов нет вовсе — показывать нечего, кроме имени файла.
  bool get isEmpty => title.isEmpty && artist.isEmpty && album.isEmpty && year.isEmpty;
}

/// Сведения о файле.
class SystemVideoInfo {
  const SystemVideoInfo({
    this.videoCodec = '',
    this.audioCodecs = const [],
    this.frameRate = 0,
    this.bitRate = 0,
    this.sampleRate = 0,
    this.channels = 0,
  });

  /// Кодек видео — как его называет система (`avc1`, `hvc1`).
  final String videoCodec;

  /// Кодеки дорожек звука, по одной строке на дорожку.
  final List<String> audioCodecs;

  /// Кадров в секунду; 0 — неизвестно.
  final double frameRate;

  /// Бит в секунду, по всем дорожкам; 0 — неизвестно.
  final int bitRate;

  /// Частота дискретизации первой звуковой дорожки, Гц; 0 — неизвестно.
  final double sampleRate;

  /// Каналов в первой звуковой дорожке; 0 — неизвестно.
  final int channels;
}

/// Где плеер сейчас.
class SystemVideoState {
  const SystemVideoState({required this.position, required this.playing, required this.ended});

  final Duration position;

  final bool playing;

  /// Доиграл до конца.
  final bool ended;
}
