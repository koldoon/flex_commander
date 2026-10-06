import AVFoundation
import Accelerate
import Cocoa
import FlutterMacOS
import MediaToolbox
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

  /// Ролики, которые играет просмотрщик видео. Живёт столько же.
  private var systemVideo: SystemVideo?

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

    // Видео: плеер держит система, кадры идут в текстуру Flutter, Dart держит
    // ручку (`docs/spec/video-viewer.md`, §3). Текстуры регистрируются через
    // регистратор — у голого канала их нет.
    systemVideo = SystemVideo(registrar: flutterViewController.registrar(forPlugin: "SystemVideo"))

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
    // Сборка — от macOS 12: ветка для систем старше 11-й была мёртвой и только
    // приносила предупреждение об устаревшем вызове в каждую сборку.
    return (UTType(filenameExtension: ext) ?? .data).identifier
  }

  /// Значок для обещанного — системный, по тому же расширению.
  private func icon(of name: String) -> NSImage {
    let ext = (name as NSString).pathExtension
    return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
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

/// Видео силами системы (`docs/spec/video-viewer.md`, §3).
///
/// Плееры живут здесь под ручкой; Dart держит ручку и номер текстуры. Кадры не
/// едут через канал: движок берёт пиксельный буфер сам, из `VideoPlayer`.
final class SystemVideo {
  static let channelName = "flex_commander/video"

  private let channel: FlutterMethodChannel
  private let textures: FlutterTextureRegistry

  /// Открытые плееры. Трогается только с главной нити.
  private var players: [Int: VideoPlayer] = [:]
  private var nextHandle = 1

  init(registrar: FlutterPluginRegistrar) {
    textures = registrar.textures
    channel = FlutterMethodChannel(name: SystemVideo.channelName, binaryMessenger: registrar.messenger)
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
      guard let path = arguments["path"] as? String else {
        result(nil)
        return
      }
      open(path, result)
      return
    }

    if call.method == "openAudio" {
      guard let path = arguments["path"] as? String else {
        result(nil)
        return
      }
      openAudio(path, result)
      return
    }

    guard let handle = arguments["handle"] as? Int else {
      result(nil)
      return
    }

    if call.method == "close" {
      players.removeValue(forKey: handle)?.close()
      result(nil)
      return
    }

    // Плеер уже закрыт: показ ушёл, а запрос догнал его. Не ошибка — отвечать
    // просто нечем.
    guard let player = players[handle] else {
      result(nil)
      return
    }

    switch call.method {
    case "play":
      player.player.play()
      result(nil)
    case "pause":
      player.player.pause()
      result(nil)
    case "seek":
      let seconds = arguments["seconds"] as? Double ?? 0
      let time = CMTime(seconds: seconds, preferredTimescale: 600)
      // Без допуска: иначе система встаёт на ближайший опорный кадр, и шаг
      // на кадр не работает.
      player.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        result(nil)
      }
    case "step":
      player.player.pause()
      player.player.currentItem?.step(byCount: arguments["frames"] as? Int ?? 1)
      result(nil)
    case "volume":
      player.player.volume = Float(arguments["volume"] as? Double ?? 1)
      result(nil)
    case "muted":
      player.player.isMuted = arguments["muted"] as? Bool ?? false
      result(nil)
    case "state":
      result(player.state())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Завести ручку на плеер. Состояние плеер шлёт Dart сам — методом `state`
  /// с ручкой, — опроса нет (`docs/spec/audio-viewer.md`, §7.5).
  private func register(_ player: VideoPlayer) -> Int {
    let handle = nextHandle
    nextHandle += 1
    players[handle] = player
    player.report { [weak self] state in
      var message = state
      message["handle"] = handle
      self?.channel.invokeMethod("state", arguments: message)
    }
    return handle
  }

  private func open(_ path: String, _ result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    Task {
      let answer: [String: Any]
      do {
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        let video = try await asset.loadTracks(withMediaType: .video).first
        guard playable else {
          answer = ["refused": "unplayable"]
          await MainActor.run { result(answer) }
          return
        }
        guard let video = video else {
          answer = ["refused": "noVideo"]
          await MainActor.run { result(answer) }
          return
        }
        let (natural, transform, frameRate, formats) = try await video.load(
          .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        var bitRate = Double(try await video.load(.estimatedDataRate))
        var audioCodecs: [String] = []
        for audio in try await asset.loadTracks(withMediaType: .audio) {
          let (rate, audioFormats) = try await audio.load(.estimatedDataRate, .formatDescriptions)
          bitRate += Double(rate)
          if let format = audioFormats.first {
            audioCodecs.append(SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType(format)))
          }
        }
        // Поворот — четвертями оборота: кадры текстуры приходят такими, какими
        // записаны, а повернуть их Dart может только так.
        let angle = atan2(transform.b, transform.a)
        let quarterTurns = (Int((angle / (.pi / 2)).rounded()) % 4 + 4) % 4
        let shown = quarterTurns % 2 == 1 ? CGSize(width: natural.height, height: natural.width) : natural
        answer = [
          "width": Double(shown.width),
          "height": Double(shown.height),
          "quarterTurns": quarterTurns,
          "duration": duration.seconds.isFinite ? duration.seconds : 0,
          "videoCodec": formats.first.map { SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "",
          "audioCodecs": audioCodecs,
          "frameRate": Double(frameRate),
          "bitRate": bitRate,
        ]
      } catch {
        await MainActor.run { result(["refused": "unplayable"]) }
        return
      }
      await MainActor.run {
        let player = VideoPlayer(asset: asset, textures: self.textures)
        let handle = self.register(player)
        var opened = answer
        opened["handle"] = handle
        opened["texture"] = player.textureId
        result(opened)
      }
    }
  }

  /// Звуковой файл: тот же плеер, только без кадров, и теги
  /// (`docs/spec/audio-viewer.md`, §2).
  private func openAudio(_ path: String, _ result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    Task {
      var answer: [String: Any]
      var track: AVAssetTrack?
      do {
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        track = audio
        guard playable else {
          await MainActor.run { result(["refused": "unplayable"]) }
          return
        }
        guard let audio = audio else {
          await MainActor.run { result(["refused": "noAudio"]) }
          return
        }
        let (rate, formats) = try await audio.load(.estimatedDataRate, .formatDescriptions)
        answer = [
          "duration": duration.seconds.isFinite ? duration.seconds : 0,
          "bitRate": Double(rate),
        ]
        if let format = formats.first {
          answer["audioCodecs"] = [SystemVideo.fourCC(CMFormatDescriptionGetMediaSubType(format))]
          if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            answer["sampleRate"] = basic.mSampleRate
            answer["channels"] = Int(basic.mChannelsPerFrame)
          }
        }
        for (key, value) in try await SystemVideo.tags(of: asset) {
          answer[key] = value
        }
      } catch {
        await MainActor.run { result(["refused": "unplayable"]) }
        return
      }
      let opened = answer
      await MainActor.run {
        let player = VideoPlayer(asset: asset, textures: nil, spectrumOf: track)
        let handle = self.register(player)
        var reply = opened
        reply["handle"] = handle
        if let spectrum = player.spectrum {
          reply["spectrum"] = spectrum.native()
        }
        result(reply)
      }
    }
  }

  /// Теги из `commonMetadata`: они общие для ID3 у mp3, атомов у m4a и
  /// комментариев Vorbis у flac. Год — из даты создания, а нет её — из ID3 и
  /// iTunes.
  static func tags(of asset: AVAsset) async throws -> [String: Any] {
    var tags: [String: Any] = [:]
    let common = try await asset.load(.commonMetadata)
    func string(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
      for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
        if let value = try? await item.load(.stringValue), !value.isEmpty {
          return value
        }
      }
      return nil
    }
    let all = try await asset.load(.metadata)
    // Комментарии Vorbis у flac в общие теги не попадают — лежат в `metadata`
    // ключами вида `vorb/TITLE` (проверено пробой на macOS 27). Чего нет в
    // общих, ищем по имени ключа.
    func byKey(_ names: [String]) async -> String? {
      for item in all {
        guard let key = item.identifier?.rawValue.split(separator: "/").last?.uppercased(), names.contains(key) else {
          continue
        }
        if let value = try? await item.load(.stringValue), !value.isEmpty {
          return value
        }
      }
      return nil
    }
    func tag(_ identifier: AVMetadataIdentifier, _ name: String) async -> String? {
      if let found = await string(identifier, in: common) {
        return found
      }
      return await byKey([name])
    }
    if let title = await tag(.commonIdentifierTitle, "TITLE") { tags["title"] = title }
    if let artist = await tag(.commonIdentifierArtist, "ARTIST") { tags["artist"] = artist }
    if let album = await tag(.commonIdentifierAlbumName, "ALBUM") { tags["album"] = album }
    var year = await string(.commonIdentifierCreationDate, in: common)
    if year == nil {
      for identifier in [AVMetadataIdentifier.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate] {
        if let found = await string(identifier, in: all) {
          year = found
          break
        }
      }
    }
    if year == nil {
      year = await byKey(["DATE", "YEAR"])
    }
    if let year = year { tags["year"] = year }
    for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork) {
      if let data = try? await item.load(.dataValue), !data.isEmpty {
        tags["artwork"] = FlutterStandardTypedData(bytes: data)
        break
      }
    }
    return tags
  }

  /// Код кодека строкой: `avc1`, `hvc1`, `aac `.
  static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
  }
}

/// Один плеер и его текстура.
///
/// Кадры снимает `AVPlayerItemVideoOutput`; движок забирает их сам через
/// `copyPixelBuffer` на своей нити, а о новом кадре узнаёт от display link — в
/// такт экрану, а не таймером.
final class VideoPlayer: NSObject, FlutterTexture {
  let player: AVPlayer
  private(set) var textureId: Int64 = 0

  /// Вывод кадров и реестр текстур; у звука — nil: кадров нет, и ни текстуры,
  /// ни такта экрана ему не нужно.
  private let output: AVPlayerItemVideoOutput?
  private let textures: FlutterTextureRegistry?
  private var displayLink: CVDisplayLink?

  /// Последний снятый кадр: его отдают, пока нового нет. Под замком — его
  /// читает нить движка, а пишет она же и display link.
  private var latest: CVPixelBuffer?
  private let lock = NSLock()

  /// Спектр того, что играет; nil — его не просили (видео) или тап не завёлся.
  let spectrum: SpectrumTap?

  init(asset: AVAsset, textures: FlutterTextureRegistry?, spectrumOf track: AVAssetTrack? = nil) {
    self.textures = textures
    let item = AVPlayerItem(asset: asset)
    // Отвод звука — только у звука: видео спектра не показывает
    // (`docs/spec/audio-viewer.md`, §7).
    if let track = track {
      let tap = SpectrumTap()
      if let mix = tap.audioMix(for: track) {
        item.audioMix = mix
        spectrum = tap
      } else {
        spectrum = nil
      }
    } else {
      spectrum = nil
    }
    if textures != nil {
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ])
      item.add(output)
      self.output = output
    } else {
      self.output = nil
    }
    player = AVPlayer(playerItem: item)
    // Доиграл — стоит на последнем кадре, а не уходит в чёрное.
    player.actionAtItemEnd = .pause
    super.init()
    if let textures = textures {
      textureId = textures.register(self)
      startDisplayLink()
    }
  }

  private func startDisplayLink() {
    var link: CVDisplayLink?
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard let link = link else {
      return
    }
    let context = Unmanaged.passUnretained(self).toOpaque()
    CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context in
      guard let context = context else {
        return kCVReturnSuccess
      }
      let player = Unmanaged<VideoPlayer>.fromOpaque(context).takeUnretainedValue()
      player.tick()
      return kCVReturnSuccess
    }, context)
    CVDisplayLinkStart(link)
    displayLink = link
  }

  /// Такт экрана: есть новый кадр — сказать движку.
  private func tick() {
    guard let output = output else {
      return
    }
    let time = output.itemTime(forHostTime: CACurrentMediaTime())
    guard output.hasNewPixelBuffer(forItemTime: time) else {
      return
    }
    let id = textureId
    DispatchQueue.main.async { [weak self] in
      self?.textures?.textureFrameAvailable(id)
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let output = output else {
      return nil
    }
    let time = output.itemTime(forHostTime: CACurrentMediaTime())
    lock.lock()
    defer { lock.unlock() }
    if output.hasNewPixelBuffer(forItemTime: time),
      let fresh = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    {
      latest = fresh
    }
    guard let frame = latest else {
      return nil
    }
    return Unmanaged.passRetained(frame)
  }

  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  /// Слать состояние в [send]: раз в четверть секунды, пока идёт время, — система
  /// зовёт и на пуске, остановке и перемотке, — и сразу по концу.
  func report(_ send: @escaping ([String: Any]) -> Void) {
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) {
      [weak self] _ in
      guard let self = self else { return }
      send(self.state())
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      // Доиграл: плеер встаёт сам (`actionAtItemEnd = .pause`), но скорость
      // в этот миг может быть ещё прежней.
      var state = self.state()
      state["ended"] = true
      state["playing"] = false
      send(state)
    }
  }

  /// Где плеер сейчас — для плашки времени.
  func state() -> [String: Any] {
    let position = player.currentTime().seconds
    let duration = player.currentItem?.duration.seconds ?? 0
    let ended = duration.isFinite && duration > 0 && position >= duration - 0.01
    return [
      "position": position.isFinite ? position : 0,
      "playing": player.rate != 0,
      "ended": ended,
    ]
  }

  /// Отпустить: звук смолкает, такт останавливается, текстура снимается.
  func close() {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
      endObserver = nil
    }
    player.pause()
    // Тап отпускается вместе с миксом: финализатор отдаст и его состояние.
    player.currentItem?.audioMix = nil
    player.replaceCurrentItem(with: nil)
    if let link = displayLink {
      CVDisplayLinkStop(link)
    }
    displayLink = nil
    if let textures = textures {
      textures.unregisterTexture(textureId)
    }
  }
}

/// Спектр того, что играет: отвод звука `MTAudioProcessingTap` и БПФ
/// (`docs/spec/audio-viewer.md`, §7).
///
/// Тап видит те же сэмплы, что уходят в динамики, и звук не трогает. На
/// звуковой нити — только сведение в моно и запись в кольцо: ни выделений
/// памяти, ни БПФ (§7.4). Спектр считает `compute()`, когда его спрашивают:
/// Dart зовёт его напрямую, через `dart:ffi`, без канала (§7.5).
final class SpectrumTap {
  static let bands = 64
  static let size = 2048
  static let lowHz: Float = 40
  static let highHz: Float = 16000
  /// Пол и потолок шкалы, дБ относительно полной шкалы.
  static let floorDb: Float = -80
  static let ceilingDb: Float = 0

  // Общее со звуковой нитью — под замком. `os_unfair_lock`, а не `NSLock`: он
  // передаёт приоритет держателю, а главная нить держит его микросекунды.
  private let lock: os_unfair_lock_t
  /// Последние `size` сэмплов моно; `written` — куда ляжет следующий.
  private let ring: UnsafeMutablePointer<Float>
  private var written = 0
  private var sampleRate: Float = 44100

  // Только звуковая нить — и `prepare` до неё.
  private var scratch: UnsafeMutablePointer<Float>?
  private var scratchCapacity = 0
  private var isFloat = true
  private var interleaved = false
  private var channels = 2

  // Только тот, кто зовёт `compute` (Dart, из одной нити): буферы БПФ
  // выделены раз и навсегда.
  private let log2n = vDSP_Length(11)
  private let setup: FFTSetup
  private let window: UnsafeMutablePointer<Float>
  private let windowed: UnsafeMutablePointer<Float>
  private let real: UnsafeMutablePointer<Float>
  private let imag: UnsafeMutablePointer<Float>
  private let power: UnsafeMutablePointer<Float>
  private let levels: UnsafeMutablePointer<Float>
  /// Бины каждой полосы; считаются заново только при смене частоты.
  private var bins: [(first: Int, last: Int)] = []
  private var binsRate: Float = 0

  init() {
    let n = SpectrumTap.size
    lock = .allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    ring = .allocate(capacity: n)
    ring.initialize(repeating: 0, count: n)
    setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    window = .allocate(capacity: n)
    vDSP_hann_window(window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    windowed = .allocate(capacity: n)
    real = .allocate(capacity: n / 2)
    imag = .allocate(capacity: n / 2)
    power = .allocate(capacity: n / 2)
    levels = .allocate(capacity: SpectrumTap.bands)
  }

  deinit {
    vDSP_destroy_fftsetup(setup)
    for buffer in [ring, window, windowed, real, imag, power, levels] {
      buffer.deallocate()
    }
    scratch?.deallocate()
    lock.deinitialize(count: 1)
    lock.deallocate()
  }

  /// Для Dart через `dart:ffi`: адрес C-функции, адрес тапа и адрес буфера
  /// полос. Адрес приходит ответом, а не поиском символа: вырезание символов в
  /// выпускной сборке ему не мешает (`docs/spec/audio-viewer.md`, §7.5).
  func native() -> [Int] {
    [
      unsafeBitCast(SpectrumTap.entry, to: Int.self),
      Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
      Int(bitPattern: levels),
    ]
  }

  /// Вход для Dart: посчитать спектр тапа в его буфер полос.
  private static let entry: @convention(c) (UnsafeMutableRawPointer?) -> Void = { tap in
    guard let tap = tap else {
      return
    }
    Unmanaged<SpectrumTap>.fromOpaque(tap).takeUnretainedValue().compute()
  }

  /// Полосы того, что звучит сейчас, 0…1, — в `levels`: БПФ последних `size`
  /// сэмплов.
  func compute() {
    let n = SpectrumTap.size
    let floatSize = MemoryLayout<Float>.stride
    os_unfair_lock_lock(lock)
    // Кольцо — по порядку, от старого сэмпла к свежему.
    memcpy(windowed, ring + written, (n - written) * floatSize)
    memcpy(windowed + (n - written), ring, written * floatSize)
    let rate = sampleRate
    os_unfair_lock_unlock(lock)

    if rate != binsRate {
      bins = SpectrumTap.bins(sampleRate: rate)
      binsRate = rate
    }
    vDSP_vmul(windowed, 1, window, 1, windowed, 1, vDSP_Length(n))
    var split = DSPSplitComplex(realp: real, imagp: imag)
    windowed.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
      vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
    }
    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
    vDSP_zvmags(&split, 1, power, 1, vDSP_Length(n / 2))
    // В каждой полосе — наибольший модуль.
    for (band, range) in bins.enumerated() {
      vDSP_maxv(power + range.first, 1, levels + band, vDSP_Length(range.last - range.first + 1))
    }
    // Масштаб: `zrip` даёт удвоенные значения, окно Ханна (нормированное)
    // — ещё половину амплитуды. Синус полной шкалы ≈ 0 дБ. Дальше децибелы
    // мощности и шкала пол…потолок → 0…1.
    let count = vDSP_Length(SpectrumTap.bands)
    var scale = 1 / Float(n * n / 4)
    vDSP_vsmul(levels, 1, &scale, levels, 1, count)
    var tiny: Float = 1e-12
    vDSP_vthr(levels, 1, &tiny, levels, 1, count)
    var reference: Float = 1
    vDSP_vdbcon(levels, 1, &reference, levels, 1, count, 0)
    let span = SpectrumTap.ceilingDb - SpectrumTap.floorDb
    var multiply = 1 / span
    var add = -SpectrumTap.floorDb / span
    vDSP_vsmsa(levels, 1, &multiply, &add, levels, 1, count)
    var low: Float = 0
    var high: Float = 1
    vDSP_vclip(levels, 1, &low, &high, levels, 1, count)
  }

  /// Бины БПФ каждой полосы: 40 Гц … 16 кГц по логарифмической шкале.
  private static func bins(sampleRate: Float) -> [(first: Int, last: Int)] {
    let top = size / 2 - 1
    let binHz = max(sampleRate, 1) / Float(size)
    let ratio = highHz / lowHz
    return (0..<bands).map { band in
      let from = lowHz * pow(ratio, Float(band) / Float(bands))
      let to = lowHz * pow(ratio, Float(band + 1) / Float(bands))
      let first = min(top, max(1, Int(from / binHz)))
      let last = min(top, max(first, Int(to / binHz)))
      return (first, last)
    }
  }

  /// Микс с тапом для звуковой дорожки; nil — тап не завёлся, и спектра не будет.
  func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
    let client = Unmanaged.passRetained(self).toOpaque()
    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0,
      clientInfo: client,
      init: { _, clientInfo, storageOut in
        storageOut.pointee = clientInfo
      },
      finalize: { tap in
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
      },
      prepare: { tap, maxFrames, format in
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
          .prepare(maxFrames: Int(maxFrames), format.pointee)
      },
      unprepare: nil,
      process: { tap, frames, _, bufferList, framesOut, flagsOut in
        guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else {
          return
        }
        Unmanaged<SpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
          .consume(bufferList, frames: Int(framesOut.pointee))
      }
    )
    var tap: MTAudioProcessingTap?
    guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
      == noErr, let made = tap
    else {
      Unmanaged<SpectrumTap>.fromOpaque(client).release()
      return nil
    }
    let parameters = AVMutableAudioMixInputParameters(track: track)
    parameters.audioTapProcessor = made
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]
    return mix
  }

  /// До звуковой нити: формат и буфер под моно — на звуковой нити память не
  /// выделяется.
  private func prepare(maxFrames: Int, _ format: AudioStreamBasicDescription) {
    scratch?.deallocate()
    scratchCapacity = max(1, maxFrames)
    scratch = .allocate(capacity: scratchCapacity)
    isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    channels = max(1, Int(format.mChannelsPerFrame))
    os_unfair_lock_lock(lock)
    sampleRate = Float(format.mSampleRate)
    os_unfair_lock_unlock(lock)
  }

  /// Звуковая нить: сэмплы — в моно, моно — в кольцо.
  private func consume(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
    guard isFloat, let mono = scratch else {
      return
    }
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let floatSize = MemoryLayout<Float>.stride
    var count = min(frames, scratchCapacity)
    // Не дальше, чем лежит в буферах.
    for buffer in buffers {
      count = min(count, Int(buffer.mDataByteSize) / (floatSize * (interleaved ? channels : 1)))
    }
    guard count > 0 else {
      return
    }
    let length = vDSP_Length(count)
    vDSP_vclr(mono, 1, length)
    if interleaved {
      guard let data = buffers.first?.mData else {
        return
      }
      let samples = data.assumingMemoryBound(to: Float.self)
      var share = 1 / Float(channels)
      for channel in 0..<channels {
        vDSP_vsma(samples + channel, vDSP_Stride(channels), &share, mono, 1, mono, 1, length)
      }
    } else {
      var share = 1 / Float(max(1, buffers.count))
      for buffer in buffers {
        guard let data = buffer.mData else { continue }
        vDSP_vsma(data.assumingMemoryBound(to: Float.self), 1, &share, mono, 1, mono, 1, length)
      }
    }
    write(mono, count)
  }

  /// Звуковая нить: блок — в кольцо, двумя копиями под замком.
  private func write(_ samples: UnsafePointer<Float>, _ count: Int) {
    let n = SpectrumTap.size
    let floatSize = MemoryLayout<Float>.stride
    // Блок длиннее окна — нужен только хвост.
    let length = min(count, n)
    let source = samples + (count - length)
    os_unfair_lock_lock(lock)
    let head = min(length, n - written)
    memcpy(ring + written, source, head * floatSize)
    memcpy(ring, source + head, (length - head) * floatSize)
    written = (written + length) % n
    os_unfair_lock_unlock(lock)
  }
}
