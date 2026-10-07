import Cocoa
import FlutterMacOS
import PDFKit

/// Документы PDF под ручками (`docs/spec/pdf-viewer.md`, §3).
///
/// Страниц сотни, рисовать надо только видимые и того размера, каким их
/// показывают сейчас, — поэтому разобранный документ держится здесь, а Dart
/// держит на него номер. Закрывает его тот, кто открыл: показ, уходя.
///
/// `PDFDocument` не обещает работы из нескольких нитей — у каждого документа
/// своя очередь: запросы одного идут по порядку, разных — параллельно.
final class SystemPdf {
  static let channelName = "flex_commander/pdf"

  /// Наибольшая отрисовка одной страницы: 16 мегапикселей. Сильнее приблизили
  /// — Dart растягивает наибольшую (§4).
  static let maxPixels = 16 * 1000 * 1000

  private let channel: FlutterMethodChannel

  private struct Open {
    let document: PDFDocument
    let queue: DispatchQueue
  }

  /// Открытые документы. Трогается только с главной нити.
  private var documents: [Int: Open] = [:]
  private var nextHandle = 1

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SystemPdf.channelName, binaryMessenger: messenger)
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
      guard let data = (arguments["bytes"] as? FlutterStandardTypedData)?.data else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let document = PDFDocument(data: data)
        let pages = document.map(SystemPdf.pageSizes) ?? []
        DispatchQueue.main.async {
          guard let document = document else {
            result(nil)
            return
          }
          let handle = self.nextHandle
          self.nextHandle += 1
          self.documents[handle] = Open(
            document: document,
            queue: DispatchQueue(label: "flex_commander.pdf.\(handle)", qos: .userInitiated)
          )
          result(["handle": handle, "pages": pages, "locked": document.isLocked])
        }
      }
      return
    }

    guard let handle = arguments["handle"] as? Int else {
      result(nil)
      return
    }

    if call.method == "close" {
      documents.removeValue(forKey: handle)
      result(nil)
      return
    }

    // Документ уже закрыт: показ ушёл, а запрос догнал его. Не ошибка —
    // отвечать просто нечем.
    guard let open = documents[handle] else {
      result(nil)
      return
    }

    let work: () -> Any?
    switch call.method {
    case "render":
      let index = arguments["page"] as? Int ?? 0
      let width = arguments["width"] as? Int ?? 0
      work = { SystemPdf.render(open.document, page: index, width: width) }
    case "find":
      let text = arguments["text"] as? String ?? ""
      let caseSensitive = arguments["caseSensitive"] as? Bool ?? false
      work = { SystemPdf.find(open.document, text: text, caseSensitive: caseSensitive) }
    case "text":
      work = { SystemPdf.text(open.document) }
    case "outline":
      work = { SystemPdf.outline(open.document) }
    case "links":
      let index = arguments["page"] as? Int ?? 0
      work = { SystemPdf.links(open.document, page: index) }
    case "select":
      let from = arguments["from"] as? [Double] ?? []
      let to = arguments["to"] as? [Double] ?? []
      let unit = arguments["unit"] as? String ?? "character"
      work = { SystemPdf.select(open.document, from: from, to: to, unit: unit) }
    case "unlock":
      let password = arguments["password"] as? String ?? ""
      // Размеры — заново: у запертого документа система может не отдать их
      // вовсе (`docs/spec/pdf-viewer.md`, §15.4).
      work = {
        open.document.unlock(withPassword: password) && !open.document.isLocked
          ? ["pages": SystemPdf.pageSizes(open.document)]
          : nil
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }

    open.queue.async {
      let answer = work()
      DispatchQueue.main.async { result(answer) }
    }
  }

  /// Показанная сторона страницы: `cropBox`, повёрнутый так, как его увидит
  /// человек.
  private static func displaySize(_ page: PDFPage) -> CGSize {
    let box = page.bounds(for: .cropBox)
    return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
  }

  private static func pageSizes(_ document: PDFDocument) -> [[Double]] {
    (0..<document.pageCount).map { index in
      guard let page = document.page(at: index) else {
        return [0, 0]
      }
      let size = displaySize(page)
      return [Double(size.width), Double(size.height)]
    }
  }

  /// Нарисовать страницу в `png`.
  ///
  /// `png`, а не `jpeg`, как у `HEIC`: на странице текст, и на нём `png` и
  /// меньше, и без ореолов вокруг букв (замер — §2.1 спецификации).
  ///
  /// Поворот страницы `draw(with:to:)` учитывает сам — проверено прототипом,
  /// и поворачивать второй раз нельзя: страница уезжает за край.
  private static func render(_ document: PDFDocument, page index: Int, width requested: Int) -> FlutterStandardTypedData? {
    guard let page = document.page(at: index), requested > 0 else {
      return nil
    }
    let size = displaySize(page)
    guard size.width > 0, size.height > 0 else {
      return nil
    }

    var width = CGFloat(requested)
    var height = (size.height * width / size.width).rounded()
    if width * height > CGFloat(maxPixels) {
      let shrink = (CGFloat(maxPixels) / (width * height)).squareRoot()
      width = (width * shrink).rounded(.down)
      height = (height * shrink).rounded(.down)
    }
    let w = max(Int(width), 1)
    let h = max(Int(height), 1)

    guard let context = CGContext(
      data: nil,
      width: w,
      height: h,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    // Бумага белая: прозрачный фон страницы иначе лёг бы на тёмную раму.
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
    page.draw(with: .cropBox, to: context)

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else {
      return nil
    }
    return FlutterStandardTypedData(bytes: png)
  }

  /// Найти строку: `[[страница, x, y, ширина, высота, x, y, …]]`, в долях
  /// показанной страницы, отсчёт сверху слева.
  ///
  /// По строкам: найденное, перенесённое на следующую строку, — два
  /// прямоугольника, а не один охватывающий через полстраницы.
  private static func find(_ document: PDFDocument, text: String, caseSensitive: Bool) -> [[Double]] {
    guard !text.isEmpty else {
      return []
    }
    let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
    var found: [[Double]] = []
    for selection in document.findString(text, withOptions: options) {
      guard let page = selection.pages.first else {
        continue
      }
      let size = displaySize(page)
      guard size.width > 0, size.height > 0 else {
        continue
      }
      // Из пространства страницы — в показанную: поворот и начало `cropBox`.
      let transform = page.transform(for: .cropBox)
      var entry: [Double] = [Double(document.index(for: page))]
      for line in selection.selectionsByLine() {
        let shown = line.bounds(for: page).applying(transform)
        guard !shown.isEmpty else {
          continue
        }
        entry += [
          Double(shown.minX / size.width),
          Double(1 - shown.maxY / size.height),
          Double(shown.width / size.width),
          Double(shown.height / size.height),
        ]
      }
      if entry.count > 1 {
        found.append(entry)
      }
    }
    return found
  }

  /// Оглавление — плоско, в порядке документа: `[уровень, название, страница,
  /// доля сверху]`; доли нет (`-1`) — к началу страницы
  /// (`docs/spec/pdf-viewer.md`, §16.4).
  private static func outline(_ document: PDFDocument) -> [[Any]] {
    guard let root = document.outlineRoot else {
      return []
    }
    var items: [[Any]] = []
    func walk(_ node: PDFOutline, depth: Int) {
      for index in 0..<node.numberOfChildren {
        guard let child = node.child(at: index) else {
          continue
        }
        let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
        if let (page, top) = target(of: destination, in: document) {
          items.append([depth, child.label ?? "", page, top])
        }
        walk(child, depth: depth + 1)
      }
    }
    walk(root, depth: 0)
    return items
  }

  /// Ссылки страницы: `[x, y, ширина, высота, страница, доля сверху]` у
  /// внутренних и `[x, y, ширина, высота, адрес]` у внешних — в долях
  /// показанной страницы, отсчёт сверху слева.
  private static func links(_ document: PDFDocument, page index: Int) -> [[Any]] {
    guard let page = document.page(at: index) else {
      return []
    }
    let size = displaySize(page)
    guard size.width > 0, size.height > 0 else {
      return []
    }
    let transform = page.transform(for: .cropBox)
    var found: [[Any]] = []
    for annotation in page.annotations {
      let shown = annotation.bounds.applying(transform)
      let rect: [Any] = [
        Double(shown.minX / size.width),
        Double(1 - shown.maxY / size.height),
        Double(shown.width / size.width),
        Double(shown.height / size.height),
      ]
      if let url = annotation.url ?? (annotation.action as? PDFActionURL)?.url {
        found.append(rect + [url.absoluteString])
        continue
      }
      let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
      if let (target, top) = target(of: destination, in: document) {
        found.append(rect + [target, top])
      }
    }
    return found
  }

  /// Место назначения — номер страницы и доля сверху в показанной странице.
  ///
  /// Неуказанная координата у PDF — огромное число (`kPDFDestinationUnspecifiedValue`):
  /// по горизонтали её почти всегда нет, и считается она нулём; нет высоты —
  /// `-1`, к началу страницы.
  private static func target(of destination: PDFDestination?, in document: PDFDocument) -> (Int, Double)? {
    guard let destination = destination, let page = destination.page else {
      return nil
    }
    let index = document.index(for: page)
    guard index != NSNotFound else {
      return nil
    }
    let point = destination.point
    let unspecified: (CGFloat) -> Bool = { $0 > 1e30 || $0.isNaN }
    if unspecified(point.y) {
      return (index, -1)
    }
    let size = displaySize(page)
    guard size.height > 0 else {
      return (index, -1)
    }
    let shown = CGPoint(x: unspecified(point.x) ? 0 : point.x, y: point.y).applying(page.transform(for: .cropBox))
    return (index, Double(min(max(1 - shown.y / size.height, 0), 1)))
  }

  /// Точка показанной страницы — `[страница, доля по ширине, доля сверху]` —
  /// в пространство самой страницы: обратным тем `transform(for:)`, которым
  /// туда переводятся найденное и ссылки. Проверено прототипом и на повёрнутой.
  private static func point(_ at: [Double], in document: PDFDocument) -> (PDFPage, CGPoint)? {
    guard at.count == 3, let page = document.page(at: Int(at[0])) else {
      return nil
    }
    let size = displaySize(page)
    let shown = CGPoint(x: CGFloat(at[1]) * size.width, y: (1 - CGFloat(at[2])) * size.height)
    return (page, shown.applying(page.transform(for: .cropBox).inverted()))
  }

  /// Выделение (`docs/spec/pdf-viewer.md`, §17.4): от точки до точки, слово
  /// или строка под точкой. Ответ — `{"rects": [[страница, x, y, ш, в, …]],
  /// "text": …}`, прямоугольники по строкам в долях показанной страницы; null
  /// — под точкой нет текста.
  private static func select(_ document: PDFDocument, from: [Double], to: [Double], unit: String) -> [String: Any]? {
    guard let (fromPage, fromPoint) = point(from, in: document) else {
      return nil
    }
    let selection: PDFSelection?
    switch unit {
    case "word":
      selection = fromPage.selectionForWord(at: fromPoint)
    case "line":
      selection = fromPage.selectionForLine(at: fromPoint)
    default:
      guard let (toPage, toPoint) = point(to, in: document) else {
        return nil
      }
      selection = document.selection(from: fromPage, at: fromPoint, to: toPage, at: toPoint)
    }
    guard let selection = selection, let text = selection.string, !text.isEmpty else {
      return nil
    }

    var rects: [[Double]] = []
    for page in selection.pages {
      let size = displaySize(page)
      guard size.width > 0, size.height > 0 else {
        continue
      }
      let transform = page.transform(for: .cropBox)
      var entry: [Double] = [Double(document.index(for: page))]
      for line in selection.selectionsByLine() {
        let shown = line.bounds(for: page).applying(transform)
        guard !shown.isEmpty else {
          continue
        }
        entry += [
          Double(shown.minX / size.width),
          Double(1 - shown.maxY / size.height),
          Double(shown.width / size.width),
          Double(shown.height / size.height),
        ]
      }
      if entry.count > 1 {
        rects.append(entry)
      }
    }
    return ["rects": rects, "text": text]
  }

  /// Весь текст: страницы под своими номерами. Пусто — текста нет вовсе.
  private static func text(_ document: PDFDocument) -> String {
    var parts: [String] = []
    var any = false
    for index in 0..<document.pageCount {
      let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !text.isEmpty {
        any = true
      }
      parts.append("— \(index + 1) —\n\n\(text)")
    }
    return any ? parts.joined(separator: "\n\n") : ""
  }
}
