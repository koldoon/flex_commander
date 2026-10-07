import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// `HEIC` — родной формат снимков с телефона: Skia его не декодирует, а система
/// декодирует (`docs/spec/image-viewer.md`, §12). Своим каналом, а не вместе со
/// значками: вопрос другой — не «чем это нарисовать», а «прочти мне это».
final class SystemImages {
  static let channelName = "flex_commander/images"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SystemImages.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "readable" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let arguments = call.arguments as? [String: Any]
    guard let data = (arguments?["bytes"] as? FlutterStandardTypedData)?.data else {
      result(nil)
      return
    }
    let maxPixels = arguments?["maxPixels"] as? Int ?? Int.max

    // Работа тяжёлая — минуем главную нить: пока идёт распаковка, окну надо
    // рисоваться.
    DispatchQueue.global(qos: .userInitiated).async {
      let answer = SystemImages.readable(data: data, maxPixels: maxPixels)
      DispatchQueue.main.async { result(answer) }
    }
  }

  /// Разобрать и пересжать в то, что Flutter покажет.
  ///
  /// **Заголовок читается отдельно и дёшево** (39 мс на снимке в 11 мегапикселей
  /// — замерено): по нему отвечаем размерами, и если точек больше, чем просили,
  /// на распаковку не тратимся вовсе.
  ///
  /// **Обратно едет `jpeg`**, а не `png` и не сырые точки: на том же снимке
  /// `png` стоит 788 мс и 7.9 МБ, сырьё — 41 МБ на канал, а `jpeg` — 44 мс и
  /// 1.8 МБ. Для показа этого достаточно, а исходник мы не трогаем: просмотрщик
  /// ничего не пишет.
  private static func readable(data: Data, maxPixels: Int) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let header = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    guard let width = header[kCGImagePropertyPixelWidth] as? Int,
          let height = header[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0
    else {
      return nil
    }

    let format = SystemImages.name(of: CGImageSourceGetType(source) as String?)
    if width * height > maxPixels {
      // Размеры без картинки: отказ словами складывает тот, кто спрашивал.
      return ["width": width, "height": height, "format": format]
    }

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
      return nil
    }

    return [
      "width": width,
      "height": height,
      "format": format,
      "bytes": FlutterStandardTypedData(bytes: jpeg),
    ]
  }

  /// Человеческое имя формата: `public.heic` → `HEIC`.
  ///
  /// Показываем **исходный** формат, а не тот, во что пересжали: в плашке
  /// человек должен видеть `HEIC`, иначе она врёт о файле.
  private static func name(of identifier: String?) -> String {
    guard let identifier = identifier, let type = UTType(identifier) else {
      return ""
    }
    if let extensionName = type.preferredFilenameExtension {
      return extensionName.uppercased()
    }
    return type.localizedDescription?.uppercased() ?? ""
  }
}
