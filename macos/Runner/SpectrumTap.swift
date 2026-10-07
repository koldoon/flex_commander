import AVFoundation
import Accelerate
import Cocoa
import MediaToolbox

/// Спектр того, что играет: отвод звука `MTAudioProcessingTap` и БПФ
/// (`docs/spec/audio-viewer.md`, §7).
///
/// Тап видит те же сэмплы, что уходят в динамики, и звук не трогает. На
/// звуковой нити — только сведение в моно и запись в кольцо: ни выделений
/// памяти, ни БПФ (§7.4). Спектр считает `compute()`, когда его спрашивают:
/// Dart зовёт его напрямую, через `dart:ffi`, без канала (§7.5).
///
/// Окна два (§7.6): полосы у́же бина короткого окна берутся из длинного —
/// иначе нижние полосы смотрели бы в один и тот же бин.
final class SpectrumTap {
  static let bands = 64
  static let lowHz: Float = 40
  static let highHz: Float = 16000
  /// Пол и потолок шкалы, дБ относительно полной шкалы.
  static let floorDb: Float = -80
  static let ceilingDb: Float = 0

  // Общее со звуковой нитью — под замком. `os_unfair_lock`, а не `NSLock`: он
  // передаёт приоритет держателю, а главная нить держит его микросекунды.
  private let lock: os_unfair_lock_t
  /// Последние `ringSize` сэмплов моно — на длинное окно; `written` — куда
  /// ляжет следующий. Размер — константой: звуковая нить не трогает объектов.
  private static let ringSize = 1 << 13
  private let ring: UnsafeMutablePointer<Float>
  private var written = 0
  private var sampleRate: Float = 44100

  // Только звуковая нить — и `prepare` до неё.
  private var scratch: UnsafeMutablePointer<Float>?
  private var scratchCapacity = 0
  private var isFloat = true
  private var interleaved = false
  private var channels = 2

  // Только тот, кто зовёт `compute` (Dart, из одной нити): буферы выделены раз
  // и навсегда.
  private let short = Transform(log2n: 11)
  private let long = Transform(log2n: 13)
  /// Кольцо, развёрнутое по порядку: от старого сэмпла к свежему.
  private let history: UnsafeMutablePointer<Float>
  private let levels: UnsafeMutablePointer<Float>
  /// Откуда каждая полоса; считается заново только при смене частоты.
  private var bins: [Band] = []
  private var binsRate: Float = 0

  /// Полоса: из какого окна и какие бины.
  private struct Band {
    let long: Bool
    let first: Int
    let last: Int
  }

  /// Одно окно БПФ со своими буферами.
  private final class Transform {
    let size: Int
    let log2n: vDSP_Length
    let setup: FFTSetup
    let window: UnsafeMutablePointer<Float>
    let windowed: UnsafeMutablePointer<Float>
    let real: UnsafeMutablePointer<Float>
    let imag: UnsafeMutablePointer<Float>
    let power: UnsafeMutablePointer<Float>
    /// Масштаб мощности: `zrip` даёт удвоенные значения, окно Ханна
    /// (нормированное) — ещё половину амплитуды. Синус полной шкалы ≈ 0 дБ.
    let scale: Float

    init(log2n: Int) {
      size = 1 << log2n
      self.log2n = vDSP_Length(log2n)
      setup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!
      window = .allocate(capacity: size)
      vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
      windowed = .allocate(capacity: size)
      real = .allocate(capacity: size / 2)
      imag = .allocate(capacity: size / 2)
      power = .allocate(capacity: size / 2)
      scale = 1 / Float(size * size / 4)
    }

    deinit {
      vDSP_destroy_fftsetup(setup)
      for buffer in [window, windowed, real, imag, power] {
        buffer.deallocate()
      }
    }

    /// Мощности бинов последних `size` сэмплов, которые кончаются в [end].
    func run(endingAt end: UnsafePointer<Float>) {
      vDSP_vmul(end - size, 1, window, 1, windowed, 1, vDSP_Length(size))
      var split = DSPSplitComplex(realp: real, imagp: imag)
      windowed.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
      }
      vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
      vDSP_zvmags(&split, 1, power, 1, vDSP_Length(size / 2))
    }
  }

  init() {
    let n = SpectrumTap.ringSize
    precondition(long.size == n)
    lock = .allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    ring = .allocate(capacity: n)
    ring.initialize(repeating: 0, count: n)
    history = .allocate(capacity: n)
    levels = .allocate(capacity: SpectrumTap.bands)
  }

  deinit {
    for buffer in [ring, history, levels] {
      buffer.deallocate()
    }
    scratch?.deallocate()
    lock.deinitialize(count: 1)
    lock.deallocate()
  }

  /// Для Dart через `dart:ffi`: адрес C-функции, адрес тапа и адрес буфера
  /// полос. Адрес приходит ответом, а не поиском символа: вырезание символов в
  /// выпускной сборке ему не мешает (`docs/spec/audio-viewer.md`, §7.5).
  func native() -> [Int] {
    [
      unsafeBitCast(SpectrumTap.entry, to: Int.self),
      Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
      Int(bitPattern: levels),
    ]
  }

  /// Вход для Dart: посчитать спектр тапа в его буфер полос.
  private static let entry: @convention(c) (UnsafeMutableRawPointer?) -> Void = { tap in
    guard let tap = tap else {
      return
    }
    Unmanaged<SpectrumTap>.fromOpaque(tap).takeUnretainedValue().compute()
  }

  /// Полосы того, что звучит сейчас, 0…1, — в `levels`.
  func compute() {
    let n = SpectrumTap.ringSize
    let floatSize = MemoryLayout<Float>.stride
    os_unfair_lock_lock(lock)
    memcpy(history, ring + written, (n - written) * floatSize)
    memcpy(history + (n - written), ring, written * floatSize)
    let rate = sampleRate
    os_unfair_lock_unlock(lock)

    if rate != binsRate {
      bins = SpectrumTap.bins(sampleRate: rate, short: short.size, long: long.size)
      binsRate = rate
    }
    // Оба окна кончаются на самом свежем сэмпле: короткое — хвост длинного.
    let end = UnsafePointer(history + n)
    short.run(endingAt: end)
    long.run(endingAt: end)
    // В каждой полосе — наибольший модуль, в масштабе своего окна.
    for (index, band) in bins.enumerated() {
      let transform = band.long ? long : short
      var peak: Float = 0
      vDSP_maxv(transform.power + band.first, 1, &peak, vDSP_Length(band.last - band.first + 1))
      levels[index] = peak * transform.scale
    }
    // Децибелы мощности и шкала пол…потолок → 0…1.
    let count = vDSP_Length(SpectrumTap.bands)
    var tiny: Float = 1e-12
    vDSP_vthr(levels, 1, &tiny, levels, 1, count)
    var reference: Float = 1
    vDSP_vdbcon(levels, 1, &reference, levels, 1, count, 0)
    let span = SpectrumTap.ceilingDb - SpectrumTap.floorDb
    var multiply = 1 / span
    var add = -SpectrumTap.floorDb / span
    vDSP_vsmsa(levels, 1, &multiply, &add, levels, 1, count)
    var low: Float = 0
    var high: Float = 1
    vDSP_vclip(levels, 1, &low, &high, levels, 1, count)
  }

  /// Откуда каждая полоса 40 Гц … 16 кГц по логарифмической шкале (§7.6).
  ///
  /// Полоса у́же бина короткого окна — из длинного. Бин относится к той
  /// полосе, куда попала его центральная частота; полосе без единого центра —
  /// ближайший к её середине бин.
  private static func bins(sampleRate: Float, short: Int, long: Int) -> [Band] {
    let rate = max(sampleRate, 1)
    let ratio = highHz / lowHz
    return (0..<bands).map { band in
      let from = lowHz * pow(ratio, Float(band) / Float(bands))
      let to = lowHz * pow(ratio, Float(band + 1) / Float(bands))
      let useLong = to - from < rate / Float(short)
      let size = useLong ? long : short
      let binHz = rate / Float(size)
      let top = size / 2 - 1
      var first = max(1, Int((from / binHz).rounded(.up)))
      var last = min(top, Int((to / binHz).rounded(.up)) - 1)
      if last < first {
        first = min(top, max(1, Int((sqrt(from * to) / binHz).rounded())))
        last = first
      }
      return Band(long: useLong, first: first, last: last)
    }
  }

  /// Микс с тапом для звуковой дорожки; nil — тап не завёлся, и спектра не будет.
  func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
    let client = Unmanaged.passRetained(self).toOpaque()
    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0,
      clientInfo: client,
      init: { _, clientInfo, storageOut in
        storageOut.pointee = clientInfo
      },
      finalize: { tap in
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
      },
      prepare: { tap, maxFrames, format in
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
          .prepare(maxFrames: Int(maxFrames), format.pointee)
      },
      unprepare: nil,
      process: { tap, frames, _, bufferList, framesOut, flagsOut in
        guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else {
          return
        }
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
          .consume(bufferList, frames: Int(framesOut.pointee))
      }
    )
    var tap: MTAudioProcessingTap?
    guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
      == noErr, let made = tap
    else {
      Unmanaged<SpectrumTap>.fromOpaque(client).release()
      return nil
    }
    let parameters = AVMutableAudioMixInputParameters(track: track)
    parameters.audioTapProcessor = made
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]
    return mix
  }

  /// До звуковой нити: формат и буфер под моно — на звуковой нити память не
  /// выделяется.
  private func prepare(maxFrames: Int, _ format: AudioStreamBasicDescription) {
    scratch?.deallocate()
    scratchCapacity = max(1, maxFrames)
    scratch = .allocate(capacity: scratchCapacity)
    isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    channels = max(1, Int(format.mChannelsPerFrame))
    os_unfair_lock_lock(lock)
    sampleRate = Float(format.mSampleRate)
    os_unfair_lock_unlock(lock)
  }

  /// Звуковая нить: сэмплы — в моно, моно — в кольцо.
  private func consume(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
    guard isFloat, let mono = scratch else {
      return
    }
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let floatSize = MemoryLayout<Float>.stride
    var count = min(frames, scratchCapacity)
    // Не дальше, чем лежит в буферах.
    for buffer in buffers {
      count = min(count, Int(buffer.mDataByteSize) / (floatSize * (interleaved ? channels : 1)))
    }
    guard count > 0 else {
      return
    }
    let length = vDSP_Length(count)
    vDSP_vclr(mono, 1, length)
    if interleaved {
      guard let data = buffers.first?.mData else {
        return
      }
      let samples = data.assumingMemoryBound(to: Float.self)
      var share = 1 / Float(channels)
      for channel in 0..<channels {
        vDSP_vsma(samples + channel, vDSP_Stride(channels), &share, mono, 1, mono, 1, length)
      }
    } else {
      var share = 1 / Float(max(1, buffers.count))
      for buffer in buffers {
        guard let data = buffer.mData else { continue }
        vDSP_vsma(data.assumingMemoryBound(to: Float.self), 1, &share, mono, 1, mono, 1, length)
      }
    }
    write(mono, count)
  }

  /// Звуковая нить: блок — в кольцо, двумя копиями под замком.
  private func write(_ samples: UnsafePointer<Float>, _ count: Int) {
    let n = SpectrumTap.ringSize
    let floatSize = MemoryLayout<Float>.stride
    // Блок длиннее окна — нужен только хвост.
    let length = min(count, n)
    let source = samples + (count - length)
    os_unfair_lock_lock(lock)
    let head = min(length, n - written)
    memcpy(ring + written, source, head * floatSize)
    memcpy(ring, source + head, (length - head) * floatSize)
    written = (written + length) % n
    os_unfair_lock_unlock(lock)
  }
}
