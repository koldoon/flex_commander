import Cocoa
import FlutterMacOS
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Значки, которые система знает об объектах.
///
/// Нативного здесь ровно столько, сколько нельзя сделать из Flutter: спросить
/// `NSWorkspace` и отрисовать `NSImage` в картинку нужного размера. **Кому**
/// какой значок и когда его вообще спрашивать, решает Dart: про правила,
/// строки и кэш он знает всё, а этот класс — ничего.
///
/// Два вопроса, а не один. У обычного файла значок зависит только от
/// расширения, и спрашивать его по пути значило бы на каталоге в тысячу строк
/// сходить в систему тысячу раз вместо десяти. По пути спрашивают то, у чего
/// значок свой: пакеты (`*.app`), тома, файлы с назначенной иконкой.
final class SystemIcons {
  static let channelName = "flex_commander/icons"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SystemIcons.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  /// Молчание — тоже ответ: значка нет. Ошибкой это не отвечается, потому что
  /// ошибкой оно и не является: иконка возьмётся следующим правилом.
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let pixels = arguments?["pixels"] as? Int ?? 32

    switch call.method {
    case "iconForPath":
      // Путь проверяется: `icon(forFile:)` на несуществующем отдаёт значок
      // «неизвестного документа», а это враньё — лучше не ответить вовсе.
      guard let path = arguments?["path"] as? String,
            FileManager.default.fileExists(atPath: path)
      else {
        result(nil)
        return
      }
      result(png(of: NSWorkspace.shared.icon(forFile: path), pixels: pixels))

    case "iconForExtension":
      guard let ext = arguments?["extension"] as? String, !ext.isEmpty else {
        result(nil)
        return
      }
      result(png(of: icon(forExtension: ext), pixels: pixels))

    // Род — последнее, что остаётся: о строке с сервера или из архива известно
    // только то, папка это или файл.
    // Миниатюра — картинка **содержимого**, а не значок типа: снимок
    // показывает себя, `pdf` — первую страницу, видео — кадр
    // (`docs/spec/file-thumbnails.md`).
    case "thumbnailForPath":
      guard let path = arguments?["path"] as? String else {
        result(nil)
        return
      }
      thumbnail(path: path, pixels: pixels, result: result)

    case "iconForKind":
      let folder = (arguments?["kind"] as? String) == "folder"
      result(png(of: NSWorkspace.shared.icon(for: folder ? .folder : .data), pixels: pixels))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Картинка содержимого — тем же, чем её рисует Finder.
  ///
  /// Просим **только** `.thumbnail`: `.all` вернуло бы значок типа, когда
  /// миниатюры нет, — а значок мы и без того умеем спросить сами, и подменять
  /// им содержимое значило бы врать. Нет миниатюры — молчим, и правило иконки
  /// возьмётся следующее.
  ///
  /// Ответ **не квадратный**: у него форма содержимого (замеры — §2 спеки).
  /// Поэтому картинка отдаётся как есть, а вписывает её в отведённое место тот,
  /// кто рисует.
  ///
  /// `scale: 1` и размер в пикселях: множитель экрана уже учтён тем, кто
  /// спрашивал, — тем же способом, что у значков.
  private func thumbnail(path: String, pixels: Int, result: @escaping FlutterResult) {
    let side = max(16, min(pixels, 1024))
    let request = QLThumbnailGenerator.Request(
      fileAt: URL(fileURLWithPath: path),
      size: CGSize(width: side, height: side),
      scale: 1,
      representationTypes: .thumbnail
    )

    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
      guard let image = thumbnail?.cgImage else {
        // Ошибка здесь — обычное дело: у архива, каталога и текста миниатюры
        // нет вовсе, и стоит этот отказ единицы миллисекунд.
        DispatchQueue.main.async { result(nil) }
        return
      }

      let bitmap = NSBitmapImageRep(cgImage: image)
      bitmap.size = NSSize(width: image.width, height: image.height)
      let data = bitmap.representation(using: .png, properties: [:])
      DispatchQueue.main.async {
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  /// Расширение опознаётся системой само: `txt` → `public.plain-text`.
  /// Не опознала — значок «просто данных», и это честный ответ.
  private func icon(forExtension ext: String) -> NSImage {
    NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
  }

  /// `NSImage` в `png` ровно того размера, который попросили.
  ///
  /// Размер приходит **в пикселях экрана**, а не в точках: на Retina
  /// 13-точечная иконка должна приехать двадцатью шестью пикселями, иначе её
  /// растянут вдвое и получится мыло. Предел сверху — чтобы опечатка в
  /// настройках не потребовала картинку в тысячу точек стороной.
  private func png(of image: NSImage, pixels: Int) -> FlutterStandardTypedData? {
    let side = max(8, min(pixels, 512))
    guard let target = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: side,
      pixelsHigh: side,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }

    target.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    image.draw(
      in: NSRect(x: 0, y: 0, width: side, height: side),
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = target.representation(using: .png, properties: [:]) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: data)
  }
}
