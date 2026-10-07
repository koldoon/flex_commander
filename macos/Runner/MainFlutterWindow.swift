import Cocoa
import FlutterMacOS
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
