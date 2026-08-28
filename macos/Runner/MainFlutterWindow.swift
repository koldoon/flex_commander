import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  /// Перетаскивание файлов в обе стороны. Живёт столько же, сколько окно.
  private var fileDrag: FileDrag?

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
    return .copy
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let drop = fileDrag, drop.carriesFiles(sender) else { return [] }
    drop.send("dragUpdated", sender)
    return .copy
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
final class FileDrag {
  static let channelName = "flex_commander/drop"

  private let channel: FlutterMethodChannel
  private unowned let window: NSWindow

  /// Событие, которым начинают перетаскивание. Кладёт его окно (`sendEvent`).
  var lastMouseEvent: NSEvent?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.channel = FlutterMethodChannel(name: FileDrag.channelName, binaryMessenger: messenger)
    self.window = window
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
      let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
      result(beginDrag(paths: paths))
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
  private func beginDrag(paths: [String]) -> Bool {
    guard !paths.isEmpty,
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
    source.onEnded = { [weak self] in
      // Отпускание кнопки прошло мимо окна — сессия забрала мышь себе. Значит
      // и запомненное событие устарело: до следующего настоящего нажатия
      // тащить нечем.
      self?.lastMouseEvent = nil
      self?.channel.invokeMethod("dragEnded", arguments: nil)
    }
    view.beginDraggingSession(with: items, event: event, source: source)
    channel.invokeMethod("dragBegan", arguments: nil)
    return true
  }

  /// Кто тащит. Отдельным объектом, потому что окно уже занято приёмом: одна и
  /// та же роль в обе стороны читалась бы вдвое хуже.
  private lazy var source = DragSource()
}

/// Источник перетаскивания: что позволено делать с тем, что мы отдали.
final class DragSource: NSObject, NSDraggingSource {
  /// Сессия кончилась — где бы её ни отпустили, в своём окне или в чужом.
  var onEnded: (() -> Void)?

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    onEnded?()
  }

  /// Только копирование — и только наружу.
  ///
  /// Не перенос: у переноса приёмник обязан сообщить, что забрал объект, и
  /// удалять его должны мы. Пока этого нет, «перенёс» означало бы потерю
  /// файла при первой же осечке — а копия не теряет ничего.
  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? .copy : []
  }
}
