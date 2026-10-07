import AVFoundation
import Cocoa
import FlutterMacOS

/// Видео силами системы (`docs/spec/video-viewer.md`, §3).
///
/// Плееры живут здесь под ручкой; Dart держит ручку и номер текстуры. Кадры не
/// едут через канал: движок берёт пиксельный буфер сам, из `VideoPlayer`.
final class SystemVideo {
  static let channelName = "flex_commander/video"

  private let channel: FlutterMethodChannel
  private let textures: FlutterTextureRegistry

  /// Открытые плееры. Трогается только с главной нити.
  private var players: [Int: VideoPlayer] = [:]
  private var nextHandle = 1

  init(registrar: FlutterPluginRegistrar) {
    textures = registrar.textures
    channel = FlutterMethodChannel(name: SystemVideo.channelName, binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    if call.method == "open" {
      guard let path = arguments["path"] as? String else {
        result(nil)
        return
      }
      open(path, result)
      return
    }

    if call.method == "openAudio" {
      guard let path = arguments["path"] as? String else {
        result(nil)
        return
      }
      openAudio(path, result)
      return
    }

    guard let handle = arguments["handle"] as? Int else {
      result(nil)
      return
    }

    if call.method == "close" {
      players.removeValue(forKey: handle)?.close()
      result(nil)
      return
    }

    // Плеер уже закрыт: показ ушёл, а запрос догнал его. Не ошибка — отвечать
    // просто нечем.
    guard let player = players[handle] else {
      result(nil)
      return
    }

    switch call.method {
    case "play":
      player.player.play()
      result(nil)
    case "pause":
      player.player.pause()
      result(nil)
    case "seek":
      let seconds = arguments["seconds"] as? Double ?? 0
      let time = CMTime(seconds: seconds, preferredTimescale: 600)
      // Без допуска: иначе система встаёт на ближайший опорный кадр, и шаг
      // на кадр не работает.
      player.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        result(nil)
      }
    case "step":
      player.player.pause()
      player.player.currentItem?.step(byCount: arguments["frames"] as? Int ?? 1)
      result(nil)
    case "volume":
      player.player.volume = Float(arguments["volume"] as? Double ?? 1)
      result(nil)
    case "muted":
      player.player.isMuted = arguments["muted"] as? Bool ?? false
      result(nil)
    case "state":
      result(player.state())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Завести ручку на плеер. Состояние плеер шлёт Dart сам — методом `state`
  /// с ручкой, — опроса нет (`docs/spec/audio-viewer.md`, §7.5).
  private func register(_ player: VideoPlayer) -> Int {
    let handle = nextHandle
    nextHandle += 1
    players[handle] = player
    player.report { [weak self] state in
      var message = state
      message["handle"] = handle
      self?.channel.invokeMethod("state", arguments: message)
    }
    return handle
  }

  private func open(_ path: String, _ result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    Task {
      let answer: [String: Any]
      do {
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        let video = try await asset.loadTracks(withMediaType: .video).first
        guard playable else {
          answer = ["refused": "unplayable"]
          await MainActor.run { result(answer) }
          return
        }
        guard let video = video else {
          answer = ["refused": "noVideo"]
          await MainActor.run { result(answer) }
          return
        }
        let (natural, transform, frameRate, formats) = try await video.load(
          .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        var bitRate = Double(try await video.load(.estimatedDataRate))
        var audioCodecs: [String] = []
        for audio in try await asset.loadTracks(withMediaType: .audio) {
          let (rate, audioFormats) = try await audio.load(.estimatedDataRate, .formatDescriptions)
          bitRate += Double(rate)
          if let format = audioFormats.first {
            audioCodecs.append(SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType(format)))
          }
        }
        // Поворот — четвертями оборота: кадры текстуры приходят такими, какими
        // записаны, а повернуть их Dart может только так.
        let angle = atan2(transform.b, transform.a)
        let quarterTurns = (Int((angle / (.pi / 2)).rounded()) % 4 + 4) % 4
        let shown = quarterTurns % 2 == 1 ? CGSize(width: natural.height, height: natural.width) : natural
        answer = [
          "width": Double(shown.width),
          "height": Double(shown.height),
          "quarterTurns": quarterTurns,
          "duration": duration.seconds.isFinite ? duration.seconds : 0,
          "videoCodec": formats.first.map { SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "",
          "audioCodecs": audioCodecs,
          "frameRate": Double(frameRate),
          "bitRate": bitRate,
        ]
      } catch {
        await MainActor.run { result(["refused": "unplayable"]) }
        return
      }
      await MainActor.run {
        let player = VideoPlayer(asset: asset, textures: self.textures)
        let handle = self.register(player)
        var opened = answer
        opened["handle"] = handle
        opened["texture"] = player.textureId
        result(opened)
      }
    }
  }

  /// Звуковой файл: тот же плеер, только без кадров, и теги
  /// (`docs/spec/audio-viewer.md`, §2).
  private func openAudio(_ path: String, _ result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    Task {
      var answer: [String: Any]
      var track: AVAssetTrack?
      do {
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        track = audio
        guard playable else {
          await MainActor.run { result(["refused": "unplayable"]) }
          return
        }
        guard let audio = audio else {
          await MainActor.run { result(["refused": "noAudio"]) }
          return
        }
        let (rate, formats) = try await audio.load(.estimatedDataRate, .formatDescriptions)
        answer = [
          "duration": duration.seconds.isFinite ? duration.seconds : 0,
          "bitRate": Double(rate),
        ]
        if let format = formats.first {
          answer["audioCodecs"] = [SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType(format))]
          if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            answer["sampleRate"] = basic.mSampleRate
            answer["channels"] = Int(basic.mChannelsPerFrame)
          }
        }
        for (key, value) in try await SystemVideo.tags(of: asset) {
          answer[key] = value
        }
      } catch {
        await MainActor.run { result(["refused": "unplayable"]) }
        return
      }
      // Неизменяемые копии: изменяемую переменную замыкание на главной нити
      // захватывать не может (Swift 6).
      let (opened, audio) = (answer, track)
      await MainActor.run {
        let player = VideoPlayer(asset: asset, textures: nil, spectrumOf: audio)
        let handle = self.register(player)
        var reply = opened
        reply["handle"] = handle
        if let spectrum = player.spectrum {
          reply["spectrum"] = spectrum.native()
        }
        result(reply)
      }
    }
  }

  /// Теги из `commonMetadata`: они общие для ID3 у mp3, атомов у m4a и
  /// комментариев Vorbis у flac. Год — из даты создания, а нет её — из ID3 и
  /// iTunes.
  static func tags(of asset: AVAsset) async throws -> [String: Any] {
    var tags: [String: Any] = [:]
    let common = try await asset.load(.commonMetadata)
    func string(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
      for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
        if let value = try? await item.load(.stringValue), !value.isEmpty {
          return value
        }
      }
      return nil
    }
    let all = try await asset.load(.metadata)
    // Комментарии Vorbis у flac в общие теги не попадают — лежат в `metadata`
    // ключами вида `vorb/TITLE` (проверено пробой на macOS 27). Чего нет в
    // общих, ищем по имени ключа.
    func byKey(_ names: [String]) async -> String? {
      for item in all {
        guard let key = item.identifier?.rawValue.split(separator: "/").last?.uppercased(), names.contains(key) else {
          continue
        }
        if let value = try? await item.load(.stringValue), !value.isEmpty {
          return value
        }
      }
      return nil
    }
    func tag(_ identifier: AVMetadataIdentifier, _ name: String) async -> String? {
      if let found = await string(identifier, in: common) {
        return found
      }
      return await byKey([name])
    }
    if let title = await tag(.commonIdentifierTitle, "TITLE") { tags["title"] = title }
    if let artist = await tag(.commonIdentifierArtist, "ARTIST") { tags["artist"] = artist }
    if let album = await tag(.commonIdentifierAlbumName, "ALBUM") { tags["album"] = album }
    var year = await string(.commonIdentifierCreationDate, in: common)
    if year == nil {
      for identifier in [AVMetadataIdentifier.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate] {
        if let found = await string(identifier, in: all) {
          year = found
          break
        }
      }
    }
    if year == nil {
      year = await byKey(["DATE", "YEAR"])
    }
    if let year = year { tags["year"] = year }
    for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork) {
      if let data = try? await item.load(.dataValue), !data.isEmpty {
        tags["artwork"] = FlutterStandardTypedData(bytes: data)
        break
      }
    }
    return tags
  }

  /// Код кодека строкой: `avc1`, `hvc1`, `aac `.
  static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
  }
}
