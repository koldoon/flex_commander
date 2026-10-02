import Cocoa
import FlutterMacOS
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import window_manager

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  /// Перетаскивание файлов в обе стороны. Живёт столько же, сколько окно.
  private var fileDrag: FileDrag?

  /// Значки, которые система знает об объектах. Тоже живёт столько же.
  private var systemIcons: SystemIcons?

  /// Разбор картинок, которых не умеет Flutter. И этот живёт столько же.
  private var systemImages: SystemImages?

  /// Документы PDF, которые показывает просмотрщик. Живёт столько же.
  private var systemPdf: SystemPdf?

  /// Что приложение знает о самом себе: версия, место на диске, процессор.
  private var appBuild: AppBuild?

  /// Файлы в буфере обмена. Живёт столько же, сколько окно и канал.
  private var clipboard: Clipboard?

  /// Перечень установленных шрифтов. Живёт столько же.
  private var systemFonts: SystemFonts?

  /// Акцентный цвет системы. Живёт столько же: он же и подписан на его смену.
  private var systemAccent: SystemAccent?

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

    // Картинки, которых не умеет Flutter: `HEIC` и всё, что система читает, а
    // Skia — нет (`docs/spec/image-viewer.md`, §12).
    systemImages = SystemImages(messenger: flutterViewController.engine.binaryMessenger)

    // Страницы PDF: документ разбирает и держит система, Dart просит
    // нарисовать видимое (`docs/spec/pdf-viewer.md`, §3).
    systemPdf = SystemPdf(messenger: flutterViewController.engine.binaryMessenger)

    // Своя версия и своё место на диске. Из Flutter их не узнать: версия лежит
    // в `Info.plist` бандла, а путь к бандлу знает только он сам
    // (`docs/spec/self-update.md`, §7).
    appBuild = AppBuild(messenger: flutterViewController.engine.binaryMessenger)

    // Файлы в буфере обмена: у Flutter он только текстовый
    // (`docs/spec/file-clipboard.md`, §2).
    clipboard = Clipboard(messenger: flutterViewController.engine.binaryMessenger)

    // Какие шрифты стоят в системе: из Flutter их перечня не узнать вовсе
    // (`docs/spec/theme-editor.md`, §12).
    systemFonts = SystemFonts(messenger: flutterViewController.engine.binaryMessenger)

    // Акцентный цвет системы: из Flutter его не узнать, а оформления macOS
    // красят им выделение, кнопку по умолчанию и обводку фокуса.
    systemAccent = SystemAccent(messenger: flutterViewController.engine.binaryMessenger)

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
