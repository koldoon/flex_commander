import Cocoa
import FlutterMacOS

/// Что приложение знает о самом себе.
///
/// Три вещи, которых нет у Flutter: версия из `Info.plist`, путь к своему
/// `.app` и процессор, под который собрано. По ним обновление решает, есть ли
/// смысл качать выпуск и куда его потом ставить (`docs/spec/self-update.md`).
final class AppBuild {
  static let channelName = "flex_commander/build"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: AppBuild.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "info" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let info = Bundle.main.infoDictionary
    result([
      // Версия выпуска и номер сборки — ровно то, что подставил workflow при
      // сборке (`--build-name`, `--build-number`).
      "version": info?["CFBundleShortVersionString"] as? String ?? "",
      "build": info?["CFBundleVersion"] as? String ?? "",
      // Путь к бандлу, а не к исполняемому файлу: подменять предстоит каталог
      // целиком.
      "bundlePath": Bundle.main.bundlePath,
      "architecture": AppBuild.architecture,
    ])
  }

  /// Процессор, под который собран **этот** двоичный файл, а не тот, на котором
  /// его запустили: под Rosetta система назвала бы x86_64, и обновление
  /// принесло бы сборку не той архитектуры.
  private static var architecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x64"
    #else
      return "unknown"
    #endif
  }
}
