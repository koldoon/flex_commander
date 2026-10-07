import Cocoa
import FlutterMacOS

/// Акцентный цвет, выбранный в системе.
///
/// Канал **двусторонний**, и этим он первый в приложении: пять прежних только
/// отвечают на вопрос. Здесь раннер ещё и заговаривает сам, потому что акцент
/// меняют в системных настройках когда угодно, а опрашивать его таймером из
/// приложения значило бы держать таймер ради события, о котором система и так
/// сообщает.
///
/// Отдаёт обе внешности сразу: оформления выбирают руками, и светлое обязано
/// взять свой акцент даже тогда, когда система стоит тёмной.
final class SystemAccent {
  static let channelName = "flex_commander/accent"

  private let channel: FlutterMethodChannel

  /// Последняя отправленная пара: присылок об одном событии бывает две, и
  /// будить приложение дважды незачем.
  private var sent: [String: Int]?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SystemAccent.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "accent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pair = SystemAccent.pair()
      self.sent = pair
      result(pair)
    }

    // AppKit сообщает о смене акцента и цвета выделения этим уведомлением, и
    // присылает его на главной нити.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(changed),
      name: NSColor.systemColorsDidChangeNotification,
      object: nil
    )

    // Вторым, для надёжности: то же событие видно и снаружи процесса. Двойная
    // присылка безвредна — отправка молчит, если пара не изменилась.
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(changed),
      name: NSNotification.Name("AppleColorPreferencesChangedNotification"),
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
  }

  @objc private func changed() {
    // Распределённое уведомление приходит не обязательно на главной нити, а
    // `NSColor` про неё: с другой он отвечает не всегда и не сразу.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let pair = SystemAccent.pair()
      guard pair != self.sent else { return }
      self.sent = pair
      self.channel.invokeMethod("changed", arguments: pair)
    }
  }

  private static func pair() -> [String: Int] {
    ["light": argb(.aqua), "dark": argb(.darkAqua)]
  }

  /// Акцент, разрешённый в заданной внешности, как `0xAARRGGBB`.
  ///
  /// Приведение к sRGB делается **внутри** блока внешности: динамический
  /// `NSColor` тянет с разрешением до того мгновения, когда у него спросят
  /// составляющие, — со внешним приведением обе внешности вернули бы одно и то
  /// же, и подмены не было бы видно, потому что числа правдоподобны.
  private static func argb(_ name: NSAppearance.Name) -> Int {
    var value = 0
    NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
      guard let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return }
      let a = Int((c.alphaComponent * 255).rounded())
      let r = Int((c.redComponent * 255).rounded())
      let g = Int((c.greenComponent * 255).rounded())
      let b = Int((c.blueComponent * 255).rounded())
      value = (a << 24) | (r << 16) | (g << 8) | b
    }
    return value
  }
}
