import Cocoa
import FlutterMacOS

/// Картинки, которых не умеет Flutter.
///
/// Перечень установленных шрифтов.
///
/// Спрашивается один раз при запуске: набор шрифтов за время работы приложения
/// не меняется. Моноширинность спрашивается у системы (`isFixedPitch` у
/// дескриптора), а не угадывается по названию: `Menlo` моноширинный, а
/// `Monotype Corsiva` — нет, и по имени этого не видно.
final class SystemFonts {
  static let channelName = "flex_commander/fonts"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SystemFonts.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "families" else {
      result(FlutterMethodNotImplemented)
      return
    }

    // Опрос семейств идёт через `NSFontManager`, а он про главную нить: с
    // другой он отвечает не всегда и не сразу.
    DispatchQueue.main.async {
      result(SystemFonts.families())
    }
  }

  private static func families() -> [[String: Any]] {
    let manager = NSFontManager.shared
    return manager.availableFontFamilies.map { family in
      // Моноширинность — свойство начертания, а не семейства: берём первое
      // объявленное, им семейство и представляется.
      // Начертание описано четвёркой `[имя, начертание, вес, признаки]`, и
      // признаки приезжают `NSNumber` — через него и берутся: прямое приведение
      // к `UInt` мостом не проходит.
      let traits = (manager.availableMembers(ofFontFamily: family)?.first?[3] as? NSNumber)?.uintValue ?? 0
      let fixedPitch = traits & NSFontTraitMask.fixedPitchFontMask.rawValue != 0
      return ["family": family, "fixedPitch": fixedPitch]
    }
  }
}
