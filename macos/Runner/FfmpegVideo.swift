import AVFoundation
import CryptoKit
import Foundation
import VideoToolbox

/// Ролик, которого система не играет, — через `ffmpeg`
/// (`docs/spec/video-via-ffmpeg.md`).
///
/// `ffmpeg` пишет HLS во временный каталог — копией, если кодеки система
/// умеет, иначе перекодированием, — а играет его прежний AVPlayer по loopback
/// HTTP. Сведения о ролике — у `ffprobe` исходного файла: о `.mkv`
/// AVFoundation не скажет ничего (§3).
final class FfmpegVideo {
  /// Почему не вышло — тем же словом, что у системного отказа.
  enum Failure: Error {
    /// `ffmpeg` или `ffprobe` на машине нет (§5).
    case needsFfmpeg
    /// Не разобрал или не сыграл и `ffmpeg`.
    case unplayable
    /// Видеодорожки нет.
    case noVideo
  }

  /// Запущенная перепаковка: её каталог, адрес и сам `ffmpeg`.
  let directory: URL
  let url: URL
  private let root: URL
  private let process: Process
  /// Что ответить Dart: размер, поворот, длительность, кодеки — у `ffprobe`.
  let answer: [String: Any]

  private init(directory: URL, root: URL, process: Process, answer: [String: Any]) {
    self.directory = directory
    self.root = root
    self.process = process
    self.answer = answer
    url = root.appendingPathComponent(FfmpegVideo.playlist)
  }

  private static let playlist = "index.m3u8"

  /// Начало имени каталога ролика во временном.
  private static let prefix = "flex_commander-video-"

  /// Каталоги, оставшиеся с прошлого запуска: приложение закрыли с открытым
  /// роликом, и убрать их было некому. Зовётся раз, при запуске, — своих
  /// среди них ещё нет, все мёртвые.
  static func sweepLeftovers() {
    let files = FileManager.default
    let temporary = files.temporaryDirectory
    let names = (try? files.contentsOfDirectory(atPath: temporary.path)) ?? []
    DispatchQueue.global(qos: .utility).async {
      for name in names where name.hasPrefix(prefix) {
        try? files.removeItem(at: temporary.appendingPathComponent(name))
      }
    }
  }

  /// Сколько ждать первого сегмента, прежде чем сдаться.
  private static let firstSegmentTimeout: TimeInterval = 20

  /// Разобрать файл и запустить перепаковку; ответ — когда в списке есть
  /// первый сегмент и играть уже можно.
  static func start(_ path: String) async throws -> FfmpegVideo {
    guard let tools = locate() else {
      throw Failure.needsFfmpeg
    }
    let probe = try await FfmpegVideo.probe(path, with: tools.ffprobe)
    guard let video = probe.video else {
      throw Failure.noVideo
    }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let copies = copiesVideo(video.codec)
    let process = Process()
    process.executableURL = tools.ffmpeg
    process.arguments = arguments(path: path, video: video, audio: probe.audio, copies: copies, into: directory)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw Failure.unplayable
    }

    // Скопированный поток несёт поворот с собой, и кадры приходят как
    // записаны; перекодированный `ffmpeg` поворачивает сам (§3).
    let quarterTurns = copies ? video.quarterTurns : 0
    let shown = quarterTurns % 2 == 1 ? (video.height, video.width) : (video.width, video.height)
    let answer: [String: Any] = [
      "width": Double(shown.0),
      "height": Double(shown.1),
      "quarterTurns": quarterTurns,
      "duration": probe.duration,
      "videoCodec": video.codec,
      "audioCodecs": probe.audioCodecs,
      "frameRate": video.frameRate,
      "bitRate": probe.bitRate,
    ]

    guard await firstSegment(in: directory, while: process) else {
      process.terminate()
      try? FileManager.default.removeItem(at: directory)
      throw Failure.unplayable
    }
    guard let root = await LoopbackServer.shared.publish(directory) else {
      process.terminate()
      try? FileManager.default.removeItem(at: directory)
      throw Failure.unplayable
    }
    return FfmpegVideo(directory: directory, root: root, process: process, answer: answer)
  }

  /// До куда ролик уже готов, в секундах; nil — готов весь: список закончен
  /// (§4). Это и рисует полоса перемотки поверх фона, как «загруженное» у
  /// онлайн-плееров.
  ///
  /// Сумма длительностей сегментов в списке. Список перечитывается, только
  /// когда вырос, — состояние спрашивают четыре раза в секунду.
  func ready() -> Double? {
    let list = directory.appendingPathComponent(FfmpegVideo.playlist)
    let size = (try? FileManager.default.attributesOfItem(atPath: list.path)[.size] as? Int) ?? 0
    readyLock.lock()
    defer { readyLock.unlock() }
    if size == readySize {
      return readyCache
    }
    guard let text = try? String(contentsOf: list, encoding: .utf8) else {
      return readyCache
    }
    readySize = size
    if text.contains("#EXT-X-ENDLIST") {
      readyCache = nil
      return nil
    }
    var total = 0.0
    for line in text.split(separator: "\n") where line.hasPrefix("#EXTINF:") {
      total += Double(line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? "") ?? 0
    }
    readyCache = total
    return total
  }

  private let readyLock = NSLock()
  private var readySize = -1
  private var readyCache: Double? = 0

  /// Остановить `ffmpeg` и убрать каталог (§2, п. 6).
  func stop() {
    LoopbackServer.shared.withdraw(root)
    if process.isRunning {
      process.terminate()
    }
    let directory = self.directory
    DispatchQueue.global(qos: .utility).async {
      // `ffmpeg` дописывает сегмент ещё мгновение после сигнала.
      Thread.sleep(forTimeInterval: 0.5)
      try? FileManager.default.removeItem(at: directory)
    }
  }

  /// MPEG-PS — `.mpg` VCD и DVD. Система его играет, но индекса у него нет, и
  /// перемотка дочитывает файл до места, **держа главную нить**: 81 с на
  /// 690 МБ с шары (проба 17 октября 2026). Приложение замирает целиком.
  /// Поэтому такие файлы идут через `ffmpeg` сразу, если он есть (§2а).
  static func prefersFfmpeg(_ path: String) -> Bool {
    ["mpg", "mpeg", "vob", "m1v", "m2v"].contains((path as NSString).pathExtension.lowercased())
      && locate() != nil
  }

  // MARK: - Миниатюра — кадр

  /// Ролики, кадр которых достаёт `ffmpeg`, когда Quick Look отказал
  /// (`docs/spec/file-thumbnails.md`, §13). Те же, что берёт просмотрщик видео,
  /// плюс `vob`: Quick Look видит в них то же, что AVFoundation, — ничего.
  private static let videoExtensions: Set<String> = [
    "mp4", "m4v", "mov", "qt", "avi", "mkv", "webm", "flv", "wmv", "3gp", "3g2", "mpg", "mpeg", "mts", "m2ts", "vob",
  ]

  /// Стоит ли спрашивать `ffmpeg`: файл — ролик, и `ffmpeg` есть.
  static func makesThumbnail(_ path: String) -> Bool {
    videoExtensions.contains((path as NSString).pathExtension.lowercased()) && locate() != nil
  }

  /// Кадр ролика png, вписанный в квадрат [side]; nil — не вышло.
  ///
  /// Кадр — с десятой части длительности: первый у роликов часто чёрный или
  /// заставка. Своего кеша у Quick Look для нас нет, а кадр стоит 80–540 мс
  /// (проба: 1080p TS с шары — дольше всех), поэтому ответ кладётся на диск
  /// — в `Caches`, ключом путь, размер, время изменения и сторона.
  static func thumbnail(_ path: String, side: Int) async -> Data? {
    guard let tools = locate() else {
      return nil
    }
    let cached = thumbnailCache(path, side: side)
    if let cached = cached, let data = try? Data(contentsOf: cached) {
      return data
    }
    let duration = (try? await probe(path, with: tools.ffprobe))?.duration ?? 0
    let scale = "scale=\(side):\(side):force_original_aspect_ratio=decrease"
    func frame(at seconds: Double) async -> Data? {
      let data = try? await run(
        tools.ffmpeg,
        [
          "-nostdin", "-loglevel", "error", "-ss", String(format: "%.3f", seconds), "-i", path, "-an", "-sn",
          "-frames:v", "1", "-vf", scale, "-f", "image2pipe", "-c:v", "png", "-",
        ])
      return data?.isEmpty == false ? data : nil
    }
    // Короткий или битый в середине — с самого начала. Не `??`: `await` в
    // нём не собирается.
    var found = await frame(at: duration * 0.1)
    if found == nil {
      found = await frame(at: 0)
    }
    guard let data = found else {
      return nil
    }
    if let cached = cached {
      try? FileManager.default.createDirectory(
        at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: cached, options: .atomic)
    }
    return data
  }

  /// Где лежит кадр этого файла этого размера; nil — файла нет.
  private static func thumbnailCache(_ path: String, side: Int) -> URL? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      return nil
    }
    let size = attributes[.size] as? Int ?? 0
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let key = SHA256.hash(data: Data("\(path)|\(size)|\(modified)|\(side)".utf8))
      .map { String(format: "%02x", $0) }.joined()
    return caches.appendingPathComponent("flex_commander/video-thumbnails/\(key).png")
  }

  // MARK: - Где ffmpeg

  /// Свой `ffmpeg` человека (§5): Homebrew на Apple Silicon и на Intel, затем
  /// `PATH`. У приложения из Finder `PATH` короткий, поэтому известные места —
  /// первыми.
  static func locate() -> (ffmpeg: URL, ffprobe: URL)? {
    var places = ["/opt/homebrew/bin", "/usr/local/bin"]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      places += path.split(separator: ":").map(String.init)
    }
    let files = FileManager.default
    for place in places {
      let ffmpeg = URL(fileURLWithPath: place).appendingPathComponent("ffmpeg")
      let ffprobe = URL(fileURLWithPath: place).appendingPathComponent("ffprobe")
      if files.isExecutableFile(atPath: ffmpeg.path), files.isExecutableFile(atPath: ffprobe.path) {
        return (ffmpeg, ffprobe)
      }
    }
    return nil
  }

  // MARK: - Что внутри — ffprobe

  struct Video {
    let codec: String
    let width: Int
    let height: Int
    let frameRate: Double
    let quarterTurns: Int
  }

  struct Probe {
    let video: Video?
    let audio: String?
    let audioCodecs: [String]
    let duration: Double
    let bitRate: Double
  }

  static func probe(_ path: String, with ffprobe: URL) async throws -> Probe {
    let output = try await run(
      ffprobe, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", path])
    guard
      let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
      let streams = json["streams"] as? [[String: Any]]
    else {
      throw Failure.unplayable
    }
    let format = json["format"] as? [String: Any] ?? [:]
    let videos = streams.filter { $0["codec_type"] as? String == "video" && !isPicture($0) }
    let audios = streams.filter { $0["codec_type"] as? String == "audio" }
    let video = videos.first.map { stream in
      Video(
        codec: stream["codec_name"] as? String ?? "",
        width: stream["width"] as? Int ?? 0,
        height: stream["height"] as? Int ?? 0,
        frameRate: rate(stream["avg_frame_rate"] as? String) ?? rate(stream["r_frame_rate"] as? String) ?? 0,
        quarterTurns: quarterTurns(of: stream))
    }
    return Probe(
      video: video,
      audio: audios.first?["codec_name"] as? String,
      audioCodecs: audios.compactMap { $0["codec_name"] as? String },
      duration: Double(format["duration"] as? String ?? "") ?? 0,
      bitRate: Double(format["bit_rate"] as? String ?? "") ?? 0)
  }

  /// Обложка в `.mkv` — тоже «видео», но из одного кадра: играть её незачем.
  private static func isPicture(_ stream: [String: Any]) -> Bool {
    (stream["disposition"] as? [String: Any])?["attached_pic"] as? Int == 1
  }

  /// `30000/1001` → 29,97.
  private static func rate(_ text: String?) -> Double? {
    guard let parts = text?.split(separator: "/"), parts.count == 2,
      let top = Double(parts[0]), let bottom = Double(parts[1]), bottom > 0, top > 0
    else {
      return nil
    }
    return top / bottom
  }

  /// Поворот из матрицы показа — четвертями оборота, как у системного
  /// открытия. У `ffprobe` он против часовой стрелки, у нас — по ней.
  private static func quarterTurns(of stream: [String: Any]) -> Int {
    var degrees = 0.0
    if let side = stream["side_data_list"] as? [[String: Any]] {
      for data in side {
        if let rotation = data["rotation"] as? Double {
          degrees = rotation
        } else if let rotation = data["rotation"] as? Int {
          degrees = Double(rotation)
        }
      }
    }
    let turns = Int((-degrees / 90).rounded())
    return (turns % 4 + 4) % 4
  }

  // MARK: - Как перепаковать

  /// Видео, которое система умеет и в HLS: копией, без потерь (§2).
  private static func copiesVideo(_ codec: String) -> Bool {
    switch codec {
    case "h264", "hevc":
      return true
    case "av1":
      return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    default:
      return false
    }
  }

  /// Звук, который AVPlayer берёт в HLS из fMP4: копией; прочий — в AAC.
  ///
  /// MP3 сюда не входит: в mp4 система его играет, а в сегментах HLS — нет
  /// («Cannot Open», проба 17 октября 2026 на `.avi` и `.flv`).
  private static func copiesAudio(_ codec: String?) -> Bool {
    ["aac", "ac3", "eac3"].contains(codec ?? "")
  }

  private static func arguments(path: String, video: Video, audio: String?, copies: Bool, into directory: URL) -> [String] {
    // `+genpts`: у AVI своих меток времени нет, и копия без них плееру не
    // годится (CoreMedia −12642, проба 17 октября 2026).
    var arguments = [
      "-nostdin", "-loglevel", "error", "-fflags", "+genpts", "-i", path, "-map", "0:v:0", "-map", "0:a:0?", "-sn",
      "-dn",
    ]
    if copies {
      arguments += ["-c:v", "copy"]
      if video.codec == "hevc" {
        // Без метки `hvc1` Apple HEVC в mp4 не берёт.
        arguments += ["-tag:v", "hvc1"]
      }
    } else {
      // Аппаратный кодер: минута 1080p VP9 — за 3,5 с (проба). Опорный кадр
      // на каждые две секунды — сегменты ровные, и перемотка идёт по ним.
      arguments += [
        "-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p",
        "-force_key_frames", "expr:gte(t,n_forced*2)",
      ]
    }
    // AAC из MPEG-TS идёт с заголовками ADTS, а в mp4 его кладут без них:
    // без фильтра `ffmpeg` падает на первом звуковом пакете, и плееру достаётся
    // битый сегмент (CoreMedia −12642, `.mp4`, который на деле TS, — живьём
    // 17 октября 2026). На AAC без ADTS фильтр ничего не делает.
    if copiesAudio(audio) {
      arguments += ["-c:a", "copy"] + (audio == "aac" ? ["-bsf:a", "aac_adtstoasc"] : [])
    } else {
      arguments += ["-c:a", "aac", "-b:a", "192k"]
    }
    arguments += [
      "-f", "hls", "-hls_segment_type", "fmp4", "-hls_playlist_type", "event", "-hls_time", "2",
      "-hls_segment_filename", directory.appendingPathComponent("segment%d.m4s").path,
      directory.appendingPathComponent(playlist).path,
    ]
    return arguments
  }

  /// Ждать, пока в списке появится сегмент; ложь — `ffmpeg` кончился без
  /// него или не успел.
  private static func firstSegment(in directory: URL, while process: Process) async -> Bool {
    let list = directory.appendingPathComponent(playlist)
    let deadline = Date().addingTimeInterval(firstSegmentTimeout)
    while Date() < deadline {
      if let text = try? String(contentsOf: list, encoding: .utf8), text.contains("#EXTINF") {
        return true
      }
      if !process.isRunning {
        // Короткий ролик мог кончиться раньше первого взгляда.
        let text = (try? String(contentsOf: list, encoding: .utf8)) ?? ""
        return process.terminationStatus == 0 && text.contains("#EXTINF")
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
  }

  /// Вывод процесса: пишет читатель, читает конец — после него, через
  /// `DispatchGroup`.
  private final class Output: @unchecked Sendable {
    var data = Data()
  }

  /// Запустить и дождаться вывода.
  ///
  /// Конец процесса — по `terminationHandler`, а не `waitUntilExit`: тот
  /// крутит цикл событий своей нити и ждёт весть о конце там, а она туда не
  /// приходит, если процесс запускали с другой. Процесс давно кончился, а
  /// ожидание стоит вечно (поймано пробой миниатюр 17 октября 2026).
  private static func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = tool
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      process.standardInput = FileHandle.nullDevice

      // Вывод читается до конца отдельно: иначе полный канал остановил бы
      // процесс, и конца бы не было вовсе.
      let reading = DispatchGroup()
      let output = Output()
      reading.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        output.data = pipe.fileHandleForReading.readDataToEndOfFile()
        reading.leave()
      }
      process.terminationHandler = { ended in
        reading.notify(queue: .global(qos: .userInitiated)) {
          if ended.terminationStatus == 0 {
            continuation.resume(returning: output.data)
          } else {
            continuation.resume(throwing: Failure.unplayable)
          }
        }
      }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        // Читатель ждёт конца канала: закрыть его, чтобы он ушёл.
        try? pipe.fileHandleForWriting.close()
        continuation.resume(throwing: Failure.unplayable)
      }
    }
  }
}
