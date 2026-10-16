import Foundation
import Network

/// HTTP только для своих: каталоги, которые `ffmpeg` пишет для AVPlayer
/// (`docs/spec/video-via-ffmpeg.md`, §2).
///
/// HLS с `file://` AVPlayer не играет вовсе, а тот же каталог по loopback HTTP —
/// играет (проба 17 октября 2026). Отсюда и сервер: только `GET` файлов из
/// опубликованных каталогов, только на `127.0.0.1`. Каталог публикуется под
/// случайной меткой — чужой процесс на машине его не угадает.
/// Один на приложение и живёт всё время: всё изменяемое трогается только с
/// [queue].
final class LoopbackServer: @unchecked Sendable {
  static let shared = LoopbackServer()

  private let queue = DispatchQueue(label: "flex_commander.loopback")
  private var listener: NWListener?
  private var port: UInt16 = 0
  /// Метка → каталог. Трогается только с [queue].
  private var published: [String: URL] = [:]
  private var waiting: [(UInt16?) -> Void] = []

  /// Опубликовать каталог; отвечает адресом его корня или nil, если сервер
  /// не поднялся.
  func publish(_ directory: URL) async -> URL? {
    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    guard let port = await start() else {
      return nil
    }
    queue.sync { published[token] = directory }
    return URL(string: "http://127.0.0.1:\(port)/\(token)/")
  }

  /// Снять каталог: дальше его файлы не отдаются.
  func withdraw(_ root: URL) {
    let token = root.pathComponents.dropFirst().first ?? ""
    queue.async { self.published.removeValue(forKey: token) }
  }

  /// Поднять слушателя, если ещё не поднят; ответ — порт.
  private func start() async -> UInt16? {
    await withCheckedContinuation { continuation in
      queue.async {
        if self.port != 0 {
          continuation.resume(returning: self.port)
          return
        }
        self.waiting.append { continuation.resume(returning: $0) }
        guard self.listener == nil else {
          return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else {
          self.finishStart(nil)
          return
        }
        listener.newConnectionHandler = { connection in
          self.serve(connection)
        }
        listener.stateUpdateHandler = { state in
          switch state {
          case .ready:
            self.port = listener.port?.rawValue ?? 0
            self.finishStart(self.port == 0 ? nil : self.port)
          case .failed, .cancelled:
            self.listener = nil
            self.port = 0
            self.finishStart(nil)
          default:
            break
          }
        }
        self.listener = listener
        listener.start(queue: self.queue)
      }
    }
  }

  private func finishStart(_ port: UInt16?) {
    let callbacks = waiting
    waiting = []
    for callback in callbacks {
      callback(port)
    }
  }

  // MARK: - Соединение: один запрос, один ответ.

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffer: Data())
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
      guard let self = self else { return }
      var buffer = buffer
      if let data = data {
        buffer.append(data)
      }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        self.answer(connection, String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
        return
      }
      // Заголовков больше, чем бывает у плеера, или соединение кончилось.
      if error != nil || done || buffer.count > 64 * 1024 {
        connection.cancel()
        return
      }
      self.receive(connection, buffer: buffer)
    }
  }

  private func answer(_ connection: NWConnection, _ head: String) {
    let lines = head.components(separatedBy: "\r\n")
    let request = lines.first?.split(separator: " ") ?? []
    guard request.count >= 2, request[0] == "GET" || request[0] == "HEAD" else {
      send(connection, status: "405 Method Not Allowed", headers: [:], body: Data())
      return
    }
    let parts = request[1].split(separator: "/").map(String.init)
    // Только «/метка/файл»: ни подкаталогов, ни `..`.
    guard parts.count == 2, let directory = published[parts[0]], LoopbackServer.isPlainName(parts[1]) else {
      send(connection, status: "404 Not Found", headers: [:], body: Data())
      return
    }
    let file = directory.appendingPathComponent(parts[1])
    guard let body = try? Data(contentsOf: file, options: .mappedIfSafe) else {
      send(connection, status: "404 Not Found", headers: [:], body: Data())
      return
    }
    var headers = ["Content-Type": LoopbackServer.type(of: file), "Accept-Ranges": "bytes"]
    // Плеер просит кусок — отдать кусок.
    if let range = LoopbackServer.range(in: lines, size: body.count) {
      headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)"
      let part = request[0] == "HEAD" ? Data() : body.subdata(in: range)
      send(connection, status: "206 Partial Content", headers: headers, body: part, length: range.count)
      return
    }
    send(connection, status: "200 OK", headers: headers, body: request[0] == "HEAD" ? Data() : body, length: body.count)
  }

  private func send(_ connection: NWConnection, status: String, headers: [String: String], body: Data, length: Int? = nil) {
    var head = "HTTP/1.1 \(status)\r\n"
    for (name, value) in headers {
      head += "\(name): \(value)\r\n"
    }
    head += "Content-Length: \(length ?? body.count)\r\nConnection: close\r\n\r\n"
    var message = Data(head.utf8)
    message.append(body)
    connection.send(content: message, completion: .contentProcessed { _ in connection.cancel() })
  }

  private static func isPlainName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".."
      && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
  }

  private static func type(of file: URL) -> String {
    switch file.pathExtension {
    case "m3u8": return "application/vnd.apple.mpegurl"
    case "ts": return "video/mp2t"
    default: return "video/mp4"
    }
  }

  /// `Range: bytes=a-b` из заголовков; nil — целиком.
  private static func range(in lines: [String], size: Int) -> Range<Int>? {
    guard
      let line = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
      let spec = line.split(separator: "=", maxSplits: 1).last
    else {
      return nil
    }
    let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map {
      Int($0.trimmingCharacters(in: .whitespaces))
    }
    guard bounds.count == 2, size > 0 else {
      return nil
    }
    let from = bounds[0] ?? max(0, size - (bounds[1] ?? 0))
    let to = min(size - 1, bounds[0] == nil ? size - 1 : (bounds[1] ?? size - 1))
    return from <= to ? from..<(to + 1) : nil
  }
}
