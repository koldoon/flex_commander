// Снимок палитры macOS: откуда взято каждое число в оформлениях «macOS Light» и
// «macOS Dark».
//
// Запуск: `swift tool/dump_macos_palette.swift`
//
// Скрипт лежит в репозитории не для сборки, а для провенанса. Таблицы цветов в
// сети врут: там публикуют значения iOS под ярлыком macOS (System Green у них
// `#34C759`, а у macOS зелёный другой), а страница гайдлайнов отдаётся
// скриптом, и текста в ней нет вовсе. Спрашивать надо не про AppKit, а сам
// AppKit — что здесь и делается.
//
// Три источника, все — авторства Apple:
//   * семантические и системные `NSColor` в обеих `NSAppearance`;
//   * шестнадцать цветов ANSI из профилей `Clear Light` и `Clear Dark`
//     системного Terminal.app (у профиля `Basic` их нет вовсе);
//   * семь ролей подсветки из тем `Default (Light)` и `Default (Dark)` Xcode.

import AppKit

// MARK: - Вывод

/// `#AARRGGBB` — тот же вид, в котором цвет лежит в теме и правится в редакторе
/// (`docs/spec/theme-editor.md`, §4).
func argb(_ color: NSColor) -> String {
    // Приведение к sRGB обязательно: часть цветов объявлена в калибровочном
    // RGB, и без перевода оттенок уезжает молча — ничем, кроме глаза, это не
    // обнаруживается.
    guard let c = color.usingColorSpace(.sRGB) else {
        return "(не приводится к sRGB)"
    }
    let a = Int((c.alphaComponent * 255).rounded())
    let r = Int((c.redComponent * 255).rounded())
    let g = Int((c.greenComponent * 255).rounded())
    let b = Int((c.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X%02X", a, r, g, b)
}

func row(_ name: String, _ light: NSColor?, _ dark: NSColor?) {
    let l = light.map(argb) ?? "—"
    let d = dark.map(argb) ?? "—"
    print(String(format: "  %-44@ %-11@ %@", name as NSString, l as NSString, d as NSString))
}

// MARK: - Семантические и системные цвета

/// Цвет, разрешённый в заданном внешнем виде.
///
/// Вид ставится на время замера — но этого мало. Динамический `NSColor` тянет
/// с разрешением до последнего: пока у него не спросят составляющие, он остаётся
/// обещанием и отвечает по виду, который будет текущим **в этот момент**.
/// Поэтому приведение к sRGB делается **внутри** блока, а не снаружи: со
/// внешним оба столбца снимаются в одном виде — том, в котором стоит система, —
/// и подмены не видно вовсе, потому что числа правдоподобны.
func resolve(_ appearance: NSAppearance, _ pick: () -> NSColor) -> NSColor {
    var out: NSColor = .clear
    appearance.performAsCurrentDrawingAppearance {
        out = pick().usingColorSpace(.sRGB) ?? pick()
    }
    return out
}

func dumpDynamic() {
    guard let aqua = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua) else {
        print("Внешние виды недоступны")
        return
    }

    let semantic: [(String, () -> NSColor)] = [
        ("labelColor", { .labelColor }),
        ("secondaryLabelColor", { .secondaryLabelColor }),
        ("tertiaryLabelColor", { .tertiaryLabelColor }),
        ("quaternaryLabelColor", { .quaternaryLabelColor }),
        ("textColor", { .textColor }),
        ("placeholderTextColor", { .placeholderTextColor }),
        ("selectedTextColor", { .selectedTextColor }),
        ("textBackgroundColor", { .textBackgroundColor }),
        ("selectedTextBackgroundColor", { .selectedTextBackgroundColor }),
        ("unemphasizedSelectedTextBackgroundColor", { .unemphasizedSelectedTextBackgroundColor }),
        ("unemphasizedSelectedTextColor", { .unemphasizedSelectedTextColor }),
        ("windowBackgroundColor", { .windowBackgroundColor }),
        ("windowFrameTextColor", { .windowFrameTextColor }),
        ("underPageBackgroundColor", { .underPageBackgroundColor }),
        ("controlBackgroundColor", { .controlBackgroundColor }),
        ("controlColor", { .controlColor }),
        ("controlTextColor", { .controlTextColor }),
        ("disabledControlTextColor", { .disabledControlTextColor }),
        ("selectedControlColor", { .selectedControlColor }),
        ("selectedControlTextColor", { .selectedControlTextColor }),
        ("alternateSelectedControlTextColor", { .alternateSelectedControlTextColor }),
        ("controlAccentColor", { .controlAccentColor }),
        ("keyboardFocusIndicatorColor", { .keyboardFocusIndicatorColor }),
        ("selectedContentBackgroundColor", { .selectedContentBackgroundColor }),
        ("unemphasizedSelectedContentBackgroundColor", { .unemphasizedSelectedContentBackgroundColor }),
        ("separatorColor", { .separatorColor }),
        ("gridColor", { .gridColor }),
        ("headerTextColor", { .headerTextColor }),
        ("shadowColor", { .shadowColor }),
        ("linkColor", { .linkColor }),
        ("highlightColor", { .highlightColor }),
        ("scrubberTexturedBackground", { .scrubberTexturedBackground }),
    ]

    print("\n=== Семантические цвета (роль -> светлый, тёмный) ===")
    for (name, pick) in semantic {
        row(name, resolve(aqua, pick), resolve(dark, pick))
    }

    print("\n--- Чередование строк списка (alternatingContentBackgroundColors) ---")
    for i in 0..<2 {
        let light = resolve(aqua) { NSColor.alternatingContentBackgroundColors[i] }
        let night = resolve(dark) { NSColor.alternatingContentBackgroundColors[i] }
        row("alternatingContentBackgroundColors[\(i)]", light, night)
    }

    let system: [(String, () -> NSColor)] = [
        ("systemRed", { .systemRed }), ("systemOrange", { .systemOrange }),
        ("systemYellow", { .systemYellow }), ("systemGreen", { .systemGreen }),
        ("systemMint", { .systemMint }), ("systemTeal", { .systemTeal }),
        ("systemCyan", { .systemCyan }), ("systemBlue", { .systemBlue }),
        ("systemIndigo", { .systemIndigo }), ("systemPurple", { .systemPurple }),
        ("systemPink", { .systemPink }), ("systemBrown", { .systemBrown }),
        ("systemGray", { .systemGray }),
    ]

    print("\n=== Системные цвета ===")
    for (name, pick) in system {
        row(name, resolve(aqua, pick), resolve(dark, pick))
    }
}

// MARK: - Шестнадцать цветов ANSI из Terminal.app

/// Порядок тот же, что у терминала: 0-7 обычные, 8-15 яркие
/// (`dependency/ui_api/lib/src/theme/app_colors.dart`, роль `terminalAnsi`).
let ansiOrder = [
    "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
    "BrightBlack", "BrightRed", "BrightGreen", "BrightYellow",
    "BrightBlue", "BrightMagenta", "BrightCyan", "BrightWhite",
]

func unarchiveColor(_ data: Data) -> NSColor? {
    // Профиль хранит цвет архивом `NSKeyedArchiver`, а не числами.
    try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
}

func dumpTerminal(_ profile: String) {
    guard
        let defaults = UserDefaults(suiteName: "com.apple.Terminal"),
        let settings = defaults.dictionary(forKey: "Window Settings"),
        let p = settings[profile] as? [String: Any]
    else {
        print("\nПрофиль «\(profile)» не найден")
        return
    }

    print("\n=== Terminal.app, профиль «\(profile)» ===")
    for key in ["BackgroundColor", "TextColor", "CursorColor", "SelectionColor"] {
        guard let data = p[key] as? Data, let color = unarchiveColor(data) else { continue }
        print("  \(key.padding(toLength: 20, withPad: " ", startingAt: 0)) \(argb(color))")
    }
    for (i, name) in ansiOrder.enumerated() {
        guard let data = p["ANSI\(name)Color"] as? Data, let color = unarchiveColor(data) else {
            print("  ansi[\(i)] \(name): нет")
            continue
        }
        print("  ansi[\(String(format: "%2d", i))] \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(argb(color))")
    }
}

// MARK: - Семь ролей подсветки из тем Xcode

/// Роль оформления -> ключ темы Xcode.
///
/// Соответствий в AppKit у подсветки нет: там нет понятия «ключевое слово
/// языка». Зато есть свои темы Apple, и числа в них лежат строкой «r g b a».
let syntaxRoles = [
    ("syntaxKeyword", "xcode.syntax.keyword"),
    ("syntaxString", "xcode.syntax.string"),
    ("syntaxNumber", "xcode.syntax.number"),
    ("syntaxComment", "xcode.syntax.comment"),
    ("syntaxType", "xcode.syntax.identifier.type"),
    ("syntaxLiteral", "xcode.syntax.identifier.constant.system"),
    ("syntaxMeta", "xcode.syntax.preprocessor"),
]

func dumpXcodeTheme(_ name: String) {
    let base = "/Applications/Xcode.app/Contents/SharedFrameworks/DVTUserInterfaceKit.framework"
    let path = "\(base)/Versions/A/Resources/FontAndColorThemes/\(name).xccolortheme"
    guard
        let data = FileManager.default.contents(atPath: path),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
        let root = plist as? [String: Any],
        let colors = root["DVTSourceTextSyntaxColors"] as? [String: String]
    else {
        print("\nТема Xcode «\(name)» не читается: \(path)")
        return
    }

    print("\n=== Xcode, тема «\(name)» ===")
    for (role, key) in syntaxRoles {
        guard let raw = colors[key] else {
            print("  \(role): ключа \(key) нет")
            continue
        }
        let parts = raw.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 3 else { continue }
        // Темы Xcode объявлены в калибровочном RGB — том же, что и профили
        // терминала.
        let color = NSColor(
            calibratedRed: parts[0], green: parts[1], blue: parts[2],
            alpha: parts.count > 3 ? parts[3] : 1
        )
        print("  \(role.padding(toLength: 16, withPad: " ", startingAt: 0)) \(argb(color)) (\(key))")
    }
}

// MARK: - Прогон

// `NSApplication` нужен, чтобы `NSColor` умел разрешаться: без приложения
// динамический цвет отвечать не обязан.
_ = NSApplication.shared

print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("Акцент, выбранный в системе сейчас: \(argb(NSColor.controlAccentColor))")

dumpDynamic()
dumpTerminal("Clear Light")
dumpTerminal("Clear Dark")
dumpXcodeTheme("Default (Light)")
dumpXcodeTheme("Default (Dark)")
