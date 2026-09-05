import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import window_manager

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  /// Перетаскивание файлов в обе стороны. Живёт столько же, сколько окно.
  private var fileDrag: FileDrag?

  /// Значки, которые система знает об объектах. Тоже живёт столько же.
  private var systemIcons: SystemIcons?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Перетаскивание файлов из Finder. Подписывается окно, а не представление
    // Flutter: своих типов оно не регистрирует, и события всё равно дошли бы
    // сюда — а окно живёт столько же, сколько канал.
    fileDrag = FileDrag(messenger: flutterViewController.engine.binaryMessenger, window: self)
    registerForDraggedTypes([.fileURL])

    // Значки Finder. Окном не пользуется вовсе — но и жить дольше него ему
    // незачем: канал закрывается вместе с движком.
    systemIcons = SystemIcons(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Последнее мышиное событие с зажатой левой кнопкой — им и начинается
  /// перетаскивание.
  ///
  /// `NSApp.currentEvent` для этого не годится, и это стоило поимки живого
  /// дефекта: просьба тащить приходит из Dart **отдельным сообщением**, уже
  /// после того, как событие обработано, и «текущим» к этому мгновению
  /// оказывается то одно, то другое — то самая протяжка, то движение мыши.
  /// Отсюда и перетаскивание, начинавшееся через раз.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown, .leftMouseDragged:
      fileDrag?.lastMouseEvent = event
    case .leftMouseUp:
      // Кнопку отпустили — тащить больше нечем: событие устарело.
      fileDrag?.lastMouseEvent = nil
    default:
      break
    }

    // Первый щелчок по неактивному окну обычно тратится на его пробуждение:
    // AppKit спрашивает у представления `acceptsFirstMouse:`, представление
    // Flutter отвечает «нет», и щелчок пропадает. В файловом менеджере это
    // особенно заметно — вернулся из Finder, ткнул в файл, а попал в пустоту и
    // тыкаешь второй раз.
    //
    // Поэтому доносим его сами. Представление Flutter подменить нечем (в
    // расширении метод не переопределить, а подменять реализацию на ходу —
    // цена, которой это не стоит), но окно вправе передать событие содержимому
    // напрямую.
    if event.type == .leftMouseDown,
       !isKeyWindow,
       // Если представление однажды научится принимать первый щелчок само,
       // доносить его будет уже некому: пришёл бы второй такой же.
       contentView?.acceptsFirstMouse(for: event) == false,
       landedInContent(event) {
      super.sendEvent(event)
      contentView?.mouseDown(with: event)
      return
    }

    super.sendEvent(event)
  }

  /// Щелчок пришёлся именно в содержимое, а не в светофор.
  ///
  /// Проверяется попаданием по всему окну, а не по `contentView`: у окна без
  /// полосы заголовка содержимое занимает его целиком, и кнопки окна лежат
  /// **поверх** — по координатам они внутри, а по дереву представлений нет.
  private func landedInContent(_ event: NSEvent) -> Bool {
    guard let content = contentView,
          let hit = content.superview?.hitTest(event.locationInWindow)
    else {
      return false
    }
    return hit == content || hit.isDescendant(of: content)
  }

  // --- приём перетаскивания (`NSDraggingDestination`) ---
  //
  // Ни одного `override`: `NSWindow` этих методов не объявляет, они приходят
  // протоколом — его класс и принимает. Проверено сборкой, а не догадкой.
  //
  // Согласие даётся сразу и на любые файлы: `draggingUpdated` обязан ответить
  // синхронно, а решает, годится ли место, Dart — асинхронно и уже по своим
  // координатам.

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let drop = fileDrag, drop.carriesFiles(sender) else { return [] }
    drop.send("dragEntered", sender)
    return drop.operation(for: sender)
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let drop = fileDrag, drop.carriesFiles(sender) else { return [] }
    drop.send("dragUpdated", sender)
    return drop.operation(for: sender)
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    fileDrag?.send("dragExited", nil)
  }

  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let drop = fileDrag, drop.carriesFiles(sender) else { return false }
    drop.send("drop", sender)
    return true
  }

  // Окно прячется до тех пор, пока приложение не восстановит сохранённые
  // положение и размер: иначе видно, как оно прыгает из положения по умолчанию.
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// Перетаскивание файлов между окном и системой — в обе стороны.
///
/// Нативного здесь ровно столько, сколько нельзя сделать из Flutter: подписка
/// на перетаскивание и перевод его в события канала. **Куда** попадут файлы,
/// решает Dart — про панели, строки и каталоги знает только он.
///
/// Ответ системе даётся сразу и всегда согласием: `draggingUpdated` обязан
/// ответить синхронно, а канал асинхронный, и ждать Dart тут нечем. Если
/// бросили не туда, Dart просто ничего не сделает; человек это видит заранее —
/// подсветку рисует он же, и её отсутствие и есть «сюда нельзя».
final class FileDrag: NSObject, NSFilePromiseProviderDelegate {
  static let channelName = "flex_commander/drop"

  private let channel: FlutterMethodChannel
  private unowned let window: NSWindow

  /// Событие, которым начинают перетаскивание. Кладёт его окно (`sendEvent`).
  var lastMouseEvent: NSEvent?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.channel = FlutterMethodChannel(name: FileDrag.channelName, binaryMessenger: messenger)
    self.window = window
    super.init()
    // Канал один на обе стороны: сюда приходят просьбы Dart, отсюда уходят
    // события системы. Два канала ради двух направлений были бы двумя именами,
    // о которых надо помнить.
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result)
    }
  }

  /// Событие перетаскивания уходит в Dart вместе с точкой и путями.
  func send(_ event: String, _ info: NSDraggingInfo?) {
    guard let info = info else {
      channel.invokeMethod(event, arguments: nil)
      return
    }
    channel.invokeMethod(event, arguments: [
      "x": point(of: info).x,
      "y": point(of: info).y,
      "paths": paths(of: info),
      "move": movesRatherThanCopies(info),
    ])
  }

  /// Точка в координатах Flutter: у него начало сверху слева, у AppKit — снизу
  /// слева, и мерить надо по `contentView`, потому что окно у нас без полосы
  /// заголовка и содержимое занимает его целиком.
  private func point(of info: NSDraggingInfo) -> CGPoint {
    guard let content = window.contentView else { return .zero }
    let inView = content.convert(info.draggingLocation, from: nil)
    return CGPoint(x: inView.x, y: content.bounds.height - inView.y)
  }

  /// Только файлы: всё остальное (текст, картинки из браузера) — не наше дело.
  private func paths(of info: NSDraggingInfo) -> [String] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    return urls?.map { $0.path } ?? []
  }

  /// Переносить, а не копировать: человек держит `Shift`.
  ///
  /// Спрашивается **и у источника**: он объявляет, что вообще позволено делать
  /// с тем, что тащит. Наружу мы, например, отдаём только копию — и никакой
  /// `Shift` этого не изменит.
  func movesRatherThanCopies(_ info: NSDraggingInfo) -> Bool {
    NSEvent.modifierFlags.contains(.shift) && info.draggingSourceOperationMask.contains(.move)
  }

  /// Что мы отвечаем системе: этим же выбирается значок у курсора — «плюс» у
  /// копии, стрелка у переноса.
  func operation(for info: NSDraggingInfo) -> NSDragOperation {
    movesRatherThanCopies(info) ? .move : .copy
  }

  /// Есть ли в пачке хоть один файл. Пустую систему тревожить незачем: на
  /// перетаскивание текста окно отвечает отказом, и курсор сразу это покажет.
  func carriesFiles(_ info: NSDraggingInfo) -> Bool {
    !paths(of: info).isEmpty
  }

  // --- отдача наружу ---

  /// Просьбы из Dart: пока одна — «начни тащить вот эти файлы».
  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "beginDrag":
      let arguments = call.arguments as? [String: Any]
      result(
        beginDrag(
          paths: arguments?["paths"] as? [String] ?? [],
          promises: arguments?["promises"] as? [[String: Any]] ?? []
        )
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Начинает перетаскивание файлов из окна.
  ///
  /// Событие берётся у приложения (`NSApp.currentEvent`): своего у Dart нет, а
  /// жест как раз идёт — палец на кнопке, и это то самое событие, которого
  /// ждёт `beginDraggingSession`. Нет события или оно не мышиное — тащить
  /// нечего, и Dart об этом узнаёт по ответу.
  private func beginDrag(paths: [String], promises: [[String: Any]]) -> Bool {
    guard !paths.isEmpty || !promises.isEmpty,
          let view = window.contentView,
          // Своё запомненное событие, а не «текущее» у приложения: см.
          // `MainFlutterWindow.sendEvent`.
          let event = lastMouseEvent
    else {
      return false
    }

    let origin = view.convert(event.locationInWindow, from: nil)
    var items: [NSDraggingItem] = []
    for (index, path) in paths.enumerated() {
      let url = URL(fileURLWithPath: path)
      let item = NSDraggingItem(pasteboardWriter: url as NSURL)
      // Значок берётся у системы — тот самый, что человек видит в Finder, — и
      // стопкой, если объектов несколько: рисовать своё, когда у системы уже
      // есть привычное, незачем.
      let icon = NSWorkspace.shared.icon(forFile: path)
      let step = CGFloat(min(index, 4)) * 4
      let frame = CGRect(x: origin.x - 16 + step, y: origin.y - 16 - step, width: 32, height: 32)
      item.setDraggingFrame(frame, contents: icon)
      items.append(item)
    }

    // Конец своей сессии виден только источнику — от него Dart и узнаёт, что
    // тащить перестали. Иначе «мы сейчас тащим» пришлось бы угадывать: наружу
    // бросают в чужом окне, и никаких событий оттуда к нам не приходит.
    source.onEnded = { [weak self] endPoint in
      guard let self = self else { return }
      // Отпускание кнопки прошло мимо окна — сессия забрала мышь себе. Значит
      // и запомненное событие устарело: до следующего настоящего нажатия
      // тащить нечем.
      self.lastMouseEvent = nil
      self.releaseMouse(at: endPoint)
      self.channel.invokeMethod("dragEnded", arguments: nil)
    }
    // Обещанное: у него нет настоящего пути, и содержимое мы отдадим, только
    // когда его попросят. До тех пор из архива ничего не читается — передумать
    // по дороге человек вправе, и распаковка ради этого была бы напрасной.
    for (index, promise) in promises.enumerated() {
      guard let id = promise["id"] as? String, let name = promise["name"] as? String else {
        continue
      }
      let provider = NSFilePromiseProvider(fileType: fileType(of: name), delegate: self)
      provider.userInfo = [FileDrag.promiseKey: id, FileDrag.nameKey: name]
      let item = NSDraggingItem(pasteboardWriter: provider)
      let step = CGFloat(min(paths.count + index, 4)) * 4
      let frame = CGRect(x: origin.x - 16 + step, y: origin.y - 16 - step, width: 32, height: 32)
      item.setDraggingFrame(frame, contents: icon(of: name))
      items.append(item)
    }

    guard !items.isEmpty else { return false }

    view.beginDraggingSession(with: items, event: event, source: source)
    channel.invokeMethod("dragBegan", arguments: nil)
    return true
  }

  static let promiseKey = "id"
  static let nameKey = "name"
  static let pathKey = "path"

  /// Чем считать обещанное. По расширению имени: настоящего файла, у которого
  /// можно было бы спросить, ещё нет.
  private func fileType(of name: String) -> String {
    let ext = (name as NSString).pathExtension
    if #available(macOS 11.0, *) {
      return (UTType(filenameExtension: ext) ?? .data).identifier
    }
    return "public.data"
  }

  /// Значок для обещанного — системный, по тому же расширению.
  private func icon(of name: String) -> NSImage {
    let ext = (name as NSString).pathExtension
    if #available(macOS 11.0, *) {
      return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
    return NSWorkspace.shared.icon(forFileType: ext)
  }

  /// Очередь, на которой выкладывается обещанное: работа с диском не должна
  /// стоять в главном потоке.
  private lazy var promises: OperationQueue = {
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    return queue
  }()

  // MARK: - NSFilePromiseProviderDelegate

  func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    (provider.userInfo as? [String: Any])?[FileDrag.nameKey] as? String ?? "file"
  }

  func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
    promises
  }

  /// Система просит обещанное — вот теперь и выкладываем.
  ///
  /// Путь назначения даёт **приёмник**, и он у всех разный: Finder называет ту
  /// папку, куда бросили, а редактор или мессенджер — свой временный каталог,
  /// из которого потом втянет содержимое к себе. Наше дело одно: написать файл
  /// ровно туда, куда сказали.
  ///
  /// Пишет его Dart — сразу в цель, без временной копии по дороге: на большом
  /// файле лишний проход по диску стоил бы столько же, сколько сама работа.
  /// Здесь не остаётся ничего тяжёлого, поэтому и главный поток свободен.
  func filePromiseProvider(
    _ provider: NSFilePromiseProvider,
    writePromiseTo url: URL,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard let id = (provider.userInfo as? [String: Any])?[FileDrag.promiseKey] as? String else {
      completionHandler(FileDragError.noSource)
      return
    }
    // Канал живёт в главном потоке, а зовут нас со своей очереди.
    DispatchQueue.main.async {
      self.channel.invokeMethod(
        "writePromise",
        arguments: [FileDrag.promiseKey: id, FileDrag.pathKey: url.path]
      ) { reply in
        completionHandler(reply as? Bool == true ? nil : FileDragError.noSource)
      }
    }
  }

  /// Досылает отпускание кнопки, которого не было.
  ///
  /// Пока идёт перетаскивание, мышь принадлежит системе, и настоящего
  /// `leftMouseUp` приложение не получает вовсе. Flutter от этого продолжает
  /// считать кнопку нажатой — а следующее нажатие для него уже не нажатие, а
  /// движение: **первый щелчок после перетаскивания пропадает**, и первая
  /// попытка потянуть снова тоже. Своё событие ставит всё на место.
  ///
  /// Ставится в начало очереди (`atStart`), чтобы попасть в приложение раньше
  /// того, что человек успеет сделать дальше.
  private func releaseMouse(at screenPoint: NSPoint) {
    let location = window.convertPoint(fromScreen: screenPoint)
    guard let event = NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: location,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 0
    ) else {
      return
    }
    NSApp.postEvent(event, atStart: true)
  }

  /// Кто тащит. Отдельным объектом, потому что окно уже занято приёмом: одна и
  /// та же роль в обе стороны читалась бы вдвое хуже.
  private lazy var source = DragSource()
}

/// Источник перетаскивания: что позволено делать с тем, что мы отдали.
final class DragSource: NSObject, NSDraggingSource {
  /// Сессия кончилась — где бы её ни отпустили, в своём окне или в чужом.
  /// Точка нужна, чтобы досланное отпускание кнопки пришло туда же, где оно и
  /// случилось.
  var onEnded: ((NSPoint) -> Void)?

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    onEnded?(screenPoint)
  }

  /// Внутри приложения — копия и перенос, наружу — только копия.
  ///
  /// Наружу не переносим потому, что удалять исходное пришлось бы нам по
  /// сообщению от чужого приложения, и «перенёс» означало бы потерю файла при
  /// первой же осечке. Внутри приложения обе стороны наши: перенос делает тот
  /// же движок, что и `F6`, — с вопросами, отменой и откатом на копию там, где
  /// переименовать нельзя.
  ///
  /// Пустой ответ для своего окна был ошибкой: он запрещал перетаскивание
  /// панель-в-панель вовсе, хотя работать оно должно именно так.
  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? .copy : [.copy, .move]
  }
}

/// Что могло пойти не так с обещанным.
enum FileDragError: Error {
  /// Содержимого не дали: приложение уже забыло, что обещало, или прочитать
  /// его не вышло.
  case noSource
}


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

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func icon(forExtension ext: String) -> NSImage {
    if #available(macOS 11.0, *) {
      return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
    return NSWorkspace.shared.icon(forFileType: ext)
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
