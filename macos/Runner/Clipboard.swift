import Cocoa
import FlutterMacOS

/// Файлы в буфере обмена системы (`docs/spec/file-clipboard.md`).
///
/// Своего буфера у Flutter нет — только текстовый; файлы знает `AppKit`, и
/// поэтому это здесь. Канал делает ровно две вещи: кладёт объекты в общий
/// буфер и рассказывает, что в нём лежит.
///
/// **Номер записи (`changeCount`) возвращается всегда.** По нему Dart узнаёт
/// своё: буфер не несёт намерения перенести, и держать это намерение можно
/// только рядом с номером той записи, к которой оно относится. Написал в буфер
/// кто-то другой — номер другой, и намерение забыто.
final class Clipboard {
  static let channelName = "flex_commander/clipboard"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Clipboard.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "write":
      let arguments = call.arguments as? [String: Any]
      result(write(paths: arguments?["paths"] as? [String] ?? [], text: arguments?["text"] as? String))
    case "read":
      result(read())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Кладёт в буфер файлы — и возвращает номер записи.
  ///
  /// Настоящие пути есть не у всех: у объекта внутри архива и на сервере их нет
  /// вовсе. Такие уходят **текстом** — адресами приложения: вставить их в
  /// Finder нельзя, а в терминал, письмо и задачу можно. Пустой записи мы при
  /// этом не оставляем: по номеру записи Dart узнаёт своё, и запись должна
  /// случиться.
  private func write(paths: [String], text: String?) -> Int {
    let board = NSPasteboard.general
    board.clearContents()

    if !paths.isEmpty {
      board.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
    } else if let text = text, !text.isEmpty {
      board.setString(text, forType: .string)
    }
    return board.changeCount
  }

  /// Что в буфере: настоящие пути файлов и номер записи.
  ///
  /// Только файлы: текст, картинки из браузера и всё прочее — не наше дело, и
  /// пустой список значит ровно это.
  private func read() -> [String: Any] {
    let board = NSPasteboard.general
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    return ["paths": urls?.map { $0.path } ?? [], "change": board.changeCount]
  }
}
