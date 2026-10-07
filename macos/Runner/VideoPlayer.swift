import AVFoundation
import Cocoa
import FlutterMacOS

/// Один плеер и его текстура.
///
/// Кадры снимает `AVPlayerItemVideoOutput`; движок забирает их сам через
/// `copyPixelBuffer` на своей нити, а о новом кадре узнаёт от display link — в
/// такт экрану, а не таймером.
final class VideoPlayer: NSObject, FlutterTexture, AVPlayerItemOutputPullDelegate {
  let player: AVPlayer
  private(set) var textureId: Int64 = 0

  /// Вывод кадров и реестр текстур; у звука — nil: кадров нет, и ни текстуры,
  /// ни такта экрана ему не нужно.
  private let output: AVPlayerItemVideoOutput?
  private let textures: FlutterTextureRegistry?
  private var displayLink: CVDisplayLink?

  /// Последний снятый кадр: его отдают, пока нового нет. Под замком — его
  /// читает нить движка, а пишет она же и display link.
  private var latest: CVPixelBuffer?
  private let lock = NSLock()

  /// Когда такт последний раз видел новый кадр. Нет их дольше [idleAfter] —
  /// такт встаёт до `outputMediaDataWillChange` (`video-viewer.md`, §2.2).
  /// Под тем же замком: пишут такт и очередь делегата.
  private var lastFrame = CACurrentMediaTime()
  private static let idleAfter: CFTimeInterval = 0.5

  /// Очередь делегата вывода — не главная: проснуться такту главная не нужна.
  private let outputQueue = DispatchQueue(label: "flex_commander.video.output")

  /// Спектр того, что играет; nil — его не просили (видео) или тап не завёлся.
  let spectrum: SpectrumTap?

  init(asset: AVAsset, textures: FlutterTextureRegistry?, spectrumOf track: AVAssetTrack? = nil) {
    self.textures = textures
    let item = AVPlayerItem(asset: asset)
    // Отвод звука — только у звука: видео спектра не показывает
    // (`docs/spec/audio-viewer.md`, §7).
    if let track = track {
      let tap = SpectrumTap()
      if let mix = tap.audioMix(for: track) {
        item.audioMix = mix
        spectrum = tap
      } else {
        spectrum = nil
      }
    } else {
      spectrum = nil
    }
    if textures != nil {
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ])
      item.add(output)
      self.output = output
    } else {
      self.output = nil
    }
    player = AVPlayer(playerItem: item)
    // Доиграл — стоит на последнем кадре, а не уходит в чёрное.
    player.actionAtItemEnd = .pause
    super.init()
    if let textures = textures {
      textureId = textures.register(self)
      // Делегат — после `super.init()`: до него `self` отдавать нельзя.
      output?.setDelegate(self, queue: outputQueue)
      startDisplayLink()
    }
  }

  private func startDisplayLink() {
    var link: CVDisplayLink?
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard let link = link else {
      return
    }
    let context = Unmanaged.passUnretained(self).toOpaque()
    CVDisplayLinkSetOutputCallback(link, { ticking, _, _, _, _, context in
      guard let context = context else {
        return kCVReturnSuccess
      }
      let player = Unmanaged<VideoPlayer>.fromOpaque(context).takeUnretainedValue()
      player.tick(ticking)
      return kCVReturnSuccess
    }, context)
    CVDisplayLinkStart(link)
    displayLink = link
  }

  /// Такт экрана: есть новый кадр — сказать движку. Нет их дольше
  /// [idleAfter] — встать и попросить вывод разбудить, когда данные пойдут:
  /// пауза и стоящий первый кадр быстрого просмотра такт не крутят (§2.2).
  private func tick(_ link: CVDisplayLink) {
    guard let output = output else {
      return
    }
    let now = CACurrentMediaTime()
    let time = output.itemTime(forHostTime: now)
    guard output.hasNewPixelBuffer(forItemTime: time) else {
      lock.lock()
      let idle = now - lastFrame > VideoPlayer.idleAfter
      lock.unlock()
      if idle {
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        CVDisplayLinkStop(link)
      }
      return
    }
    lock.lock()
    lastFrame = now
    lock.unlock()
    let id = textureId
    DispatchQueue.main.async { [weak self] in
      self?.textures?.textureFrameAvailable(id)
    }
  }

  /// Вывод: данные вот-вот пойдут — пуск, перемотка, шаг на кадр. Такт
  /// просыпается (§2.2).
  func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
    lock.lock()
    lastFrame = CACurrentMediaTime()
    let link = displayLink
    lock.unlock()
    if let link = link, !CVDisplayLinkIsRunning(link) {
      CVDisplayLinkStart(link)
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let output = output else {
      return nil
    }
    let time = output.itemTime(forHostTime: CACurrentMediaTime())
    lock.lock()
    defer { lock.unlock() }
    if output.hasNewPixelBuffer(forItemTime: time),
      let fresh = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    {
      latest = fresh
    }
    guard let frame = latest else {
      return nil
    }
    return Unmanaged.passRetained(frame)
  }

  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  /// Слать состояние в [send]: раз в четверть секунды, пока идёт время, — система
  /// зовёт и на пуске, остановке и перемотке, — и сразу по концу.
  func report(_ send: @escaping ([String: Any]) -> Void) {
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) {
      [weak self] _ in
      guard let self = self else { return }
      send(self.state())
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      // Доиграл: плеер встаёт сам (`actionAtItemEnd = .pause`), но скорость
      // в этот миг может быть ещё прежней.
      var state = self.state()
      state["ended"] = true
      state["playing"] = false
      send(state)
    }
  }

  /// Где плеер сейчас — для плашки времени.
  func state() -> [String: Any] {
    let position = player.currentTime().seconds
    let duration = player.currentItem?.duration.seconds ?? 0
    let ended = duration.isFinite && duration > 0 && position >= duration - 0.01
    return [
      "position": position.isFinite ? position : 0,
      "playing": player.rate != 0,
      "ended": ended,
    ]
  }

  /// Отпустить: звук смолкает, такт останавливается, текстура снимается.
  func close() {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
      endObserver = nil
    }
    player.pause()
    // Тап отпускается вместе с миксом: финализатор отдаст и его состояние.
    player.currentItem?.audioMix = nil
    player.replaceCurrentItem(with: nil)
    // Сперва делегат: запоздавшее «данные пойдут» не должно снова завести
    // такт закрытого плеера.
    output?.setDelegate(nil, queue: nil)
    lock.lock()
    let link = displayLink
    displayLink = nil
    lock.unlock()
    if let link = link {
      CVDisplayLinkStop(link)
    }
    if let textures = textures {
      textures.unregisterTexture(textureId)
    }
  }
}
