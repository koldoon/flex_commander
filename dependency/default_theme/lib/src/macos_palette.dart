import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Тона одной внешности macOS: всё, что снято с системы.
///
/// Отдельный набор именно **исходных** значений, как и [FcPalette] у
/// референсной темы: по нему видно, откуда взято каждое число, и его можно
/// сверить с системой заново. Роли (что чем красится) живут в `MacOsColors`.
///
/// Снято скриптом `tool/dump_macos_palette.swift` на macOS 27.0 (26A428),
/// системный акцент — Blue. Скрипт лежит в репозитории затем, чтобы числа можно
/// было переснять: **сторонние таблицы цветов macOS непригодны** — они публикуют
/// значения iOS под теми же названиями. Наглядно: `systemGreen` у них
/// `#34C759`, и это действительно iOS; у macOS 27 светлый зелёный совпал, а
/// тёмный — `#30D158`, и совпадение первого ничего не говорит о втором.
///
/// Ещё одна причина снимать, а не списывать: **гайдлайны отстают от системы**.
/// Опубликованный `systemBlue` — `rgb(0,122,255)` и `rgb(10,132,255)`, а macOS 27
/// отдаёт `#0088FF` и `#0091FF`. Акцент «Blue» при этом по-прежнему `#007AFF`:
/// это разные вещи, и путать их нельзя.
class MacOsTones {
  const MacOsTones({
    required this.brightness,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.text,
    required this.placeholder,
    required this.headerText,
    required this.controlText,
    required this.onAccentText,
    required this.windowBackground,
    required this.contentBackground,
    required this.control,
    required this.card,
    required this.unemphasizedSelection,
    required this.separator,
    required this.grid,
    required this.scrim,
    required this.pressed,
    required this.systemRed,
    required this.systemOrange,
    required this.ansi,
    required this.ansiText,
    required this.ansiCursor,
    required this.ansiSelection,
    required this.syntaxKeyword,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxComment,
    required this.syntaxType,
    required this.syntaxLiteral,
    required this.syntaxMeta,
  });

  /// Светлая внешность или тёмная. Уезжает в `FcThemeSpec.brightness`, а оттуда
  /// в `ThemeData`: полосы прокрутки и курсор в полях спрашивают именно её.
  final Brightness brightness;

  // --- подписи: `NSColor`, иерархия важности ---

  /// `labelColor` — основная подпись.
  final Color label;

  /// `secondaryLabelColor` — подпись поменьше важностью.
  final Color secondaryLabel;

  /// `tertiaryLabelColor` — недоступное и подсказки.
  final Color tertiaryLabel;

  /// `textColor` — набираемый текст. В отличие от [label] непрозрачен.
  final Color text;

  /// `placeholderTextColor` — подсказка в пустом поле.
  final Color placeholder;

  /// `headerTextColor` — заголовок колонки.
  final Color headerText;

  /// `controlTextColor` — подпись элемента управления.
  final Color controlText;

  /// `alternateSelectedControlTextColor` — подпись поверх акцента.
  ///
  /// У системы он белый в обеих внешностях: все восемь системных акцентов
  /// достаточно темны. Но акцент бывает и назначенным вручную, вплоть до почти
  /// белого, — поэтому роль не берёт его напрямую (см. `MacOsColors.onAccent`).
  final Color onAccentText;

  // --- поверхности ---

  /// Подложка, на которой стоит содержимое: `underPageBackgroundColor`.
  ///
  /// **Не `windowBackgroundColor`**, и это не вольность. В macOS 27
  /// `windowBackgroundColor` и `controlBackgroundColor` сошлись в одно значение
  /// (`#FFFFFF` на светлой, `#1E1E1E` на тёмной) — панель на таком фоне
  /// пропадает, а панелей у файлового менеджера две, и граница между ними
  /// несёт смысл. `underPageBackgroundColor` — это буквально «то, что за
  /// страницей», ровно нужная роль.
  final Color windowBackground;

  /// `controlBackgroundColor` — подложка списка: в AppKit это фон `NSTableView`.
  final Color contentBackground;

  /// `controlColor` — лицо элемента управления: кнопки, плашки.
  final Color control;

  /// Приподнятая карточка: раздел настроек, раздел сведений, список находок.
  ///
  /// **Прозрачностью, а не цветом**, и это единственный способ, который здесь
  /// работает. Карточка встаёт то на фон окна команды, то прямо на панель —
  /// полноэкранные экраны (сведения об объекте, находки) рисуются поверх неё, —
  /// и любой сплошной цвет совпадёт с одной из двух поверхностей и пропадёт.
  /// Прозрачный тон считается от того, на чём лежит, и приподнят всегда.
  ///
  /// Вес взят у `alternatingContentBackgroundColors[1]`: на светлой это
  /// `#F4F5F5`, то есть белый, убавленный примерно на четыре процента, — тем же
  /// и берём. На тёмной AppKit прямо и даёт белый пятипроцентный.
  final Color card;

  /// `unemphasizedSelectedContentBackgroundColor` — выделенное, но не в фокусе.
  final Color unemphasizedSelection;

  /// `separatorColor` — разделительная линия.
  final Color separator;

  /// `gridColor` — сетка `NSTableView`. Значение отличается от [separator], и
  /// роль тоже своя: одинаковые числа не делают две роли одной.
  final Color grid;

  /// Затемнение под окном команды.
  ///
  /// Соответствия в AppKit нет: macOS под модальным листом не затемняет вовсе.
  /// Чёрный с подобранным весом — а не фон окна с прозрачностью, как в
  /// референсе: на светлой теме тот рецепт подложку **осветлял** бы.
  final Color scrim;

  /// Нажатая кнопка. Плоского цвета для этого состояния в AppKit нет.
  /// На тёмной — осветление: затемнение на тёмном не читается.
  final Color pressed;

  /// `systemRed` — отказ и ошибка.
  final Color systemRed;

  /// `systemOrange` — пометка.
  ///
  /// Системный цвет, но **нарочно не акцентный**: курсор теперь акцентный, и
  /// будь пометка тоже акцентной, помеченная строка под курсором стала бы
  /// неотличимой. Оранжевым же система красит метки в Finder.
  final Color systemOrange;

  // --- терминал: профиль Terminal.app ---

  /// Шестнадцать цветов ANSI: 0-7 обычные, 8-15 яркие.
  ///
  /// Профили `Clear Light` и `Clear Dark` системного терминала. **Не «Basic»**:
  /// у него цветов ANSI нет вовсе — ни в бандле Terminal.app, ни в настройках,
  /// он полагается на умолчания, зашитые в код. Из двенадцати встроенных
  /// профилей полный набор есть только у этих двух, и они же разведены по
  /// яркости фона — то есть ровно то, что нужно.
  final List<Color> ansi;

  /// `TextColor` профиля — чем набран вывод, не назвавший своего цвета.
  final Color ansiText;

  /// `CursorColor` профиля. У `Clear Dark` его нет — взят текст с прозрачностью,
  /// тем же рецептом, каким сделан `FcPalette.ansiCursor`.
  final Color ansiCursor;

  /// `SelectionColor` профиля.
  final Color ansiSelection;

  // --- подсветка: темы Xcode ---

  /// `xcode.syntax.keyword` темы `Default (Light)` или `Default (Dark)`.
  ///
  /// Соответствий в AppKit у подсветки нет — там нет понятия «ключевое слово
  /// языка». Зато есть свои темы Apple, и семь наших ролей ложатся на них одна
  /// в одну. Значения там объявлены в калибровочном RGB, поэтому приведены к
  /// sRGB: без приведения `keyword` вышел бы `#9B2393` вместо `#AD3DA4`.
  final Color syntaxKeyword;

  /// `xcode.syntax.string`.
  final Color syntaxString;

  /// `xcode.syntax.number`.
  final Color syntaxNumber;

  /// `xcode.syntax.comment`.
  final Color syntaxComment;

  /// `xcode.syntax.identifier.type`.
  final Color syntaxType;

  /// `xcode.syntax.identifier.constant.system` — `true`, `null`, встроенные имена.
  final Color syntaxLiteral;

  /// `xcode.syntax.preprocessor` — директивы и то, что стоит вокруг кода.
  final Color syntaxMeta;
}

/// Акцент, когда спросить систему некого.
///
/// Канала нет в тестах и на другой платформе. Значение — то, которое отдаёт
/// `controlAccentColor` при выбранном акценте «Blue»; оно одинаково в обеих
/// внешностях, потому что акцент — выбор человека, а не свойство внешности.
const Color macOsBlueAccent = Color(0xFF007AFF);

/// Светлая внешность (`NSAppearance.aqua`).
const MacOsTones macOsLightTones = MacOsTones(
  brightness: Brightness.light,
  label: Color(0xD8000000),
  secondaryLabel: Color(0x7F000000),
  tertiaryLabel: Color(0x42000000),
  text: Color(0xFF000000),
  placeholder: Color(0x7F000000),
  headerText: Color(0xD8000000),
  controlText: Color(0xD8000000),
  onAccentText: Color(0xFFFFFFFF),
  windowBackground: Color(0xFFF6F6F6),
  contentBackground: Color(0xFFFFFFFF),
  control: Color(0xFFFFFFFF),
  card: Color(0x0A000000),
  unemphasizedSelection: Color(0xFFDCDCDC),
  separator: Color(0x19000000),
  grid: Color(0xFFE6E6E6),
  // Вес подобран замером: текст под затемнением должен упасть по контрасту
  // ниже `tertiaryLabelColor`, иначе окно команды не читается как главное.
  scrim: Color(0x33000000),
  pressed: Color(0x1A000000),
  systemRed: Color(0xFFFF383C),
  systemOrange: Color(0xFFFF8D28),
  ansi: <Color>[
    Color(0xFF2D3840),
    Color(0xFFB45648),
    Color(0xFF6CAA71),
    Color(0xFFC4AC62),
    Color(0xFF5685A8),
    Color(0xFFAD64BE),
    Color(0xFF69C6C9),
    Color(0xFFC1C8CC),
    Color(0xFF506573),
    Color(0xFFDF6C5A),
    Color(0xFF79BE7E),
    Color(0xFFE5C872),
    Color(0xFF49A2E1),
    Color(0xFFD389E5),
    Color(0xFF77E1E5),
    Color(0xFFD8E1E7),
  ],
  ansiText: Color(0xFF3A4851),
  ansiCursor: Color(0xFF919191),
  ansiSelection: Color(0xFFE5ECF1),
  syntaxKeyword: Color(0xFFAD3DA4),
  syntaxString: Color(0xFFD12F1B),
  syntaxNumber: Color(0xFF272AD8),
  syntaxComment: Color(0xFF707F8C),
  syntaxType: Color(0xFF23575C),
  syntaxLiteral: Color(0xFF804FB8),
  syntaxMeta: Color(0xFF78492A),
);

/// Тёмная внешность (`NSAppearance.darkAqua`).
const MacOsTones macOsDarkTones = MacOsTones(
  brightness: Brightness.dark,
  label: Color(0xD8FFFFFF),
  secondaryLabel: Color(0x8CFFFFFF),
  tertiaryLabel: Color(0x3FFFFFFF),
  text: Color(0xFFFFFFFF),
  placeholder: Color(0x8CFFFFFF),
  headerText: Color(0xFFFFFFFF),
  controlText: Color(0xD8FFFFFF),
  onAccentText: Color(0xFFFFFFFF),
  // Тёмная подложка **светлее** содержимого: `underPageBackgroundColor` даёт
  // `#282828` против `#1E1E1E` у списка. Светлая пара расходится в другую
  // сторону — и это правило macOS, а не наша непоследовательность: содержимое
  // отделено от подложки, а куда именно — решает внешность.
  windowBackground: Color(0xFF282828),
  contentBackground: Color(0xFF1E1E1E),
  control: Color(0x3FFFFFFF),
  card: Color(0x0CFFFFFF),
  unemphasizedSelection: Color(0xFF464646),
  separator: Color(0x19FFFFFF),
  grid: Color(0xFF1A1A1A),
  scrim: Color(0x66000000),
  pressed: Color(0x1AFFFFFF),
  systemRed: Color(0xFFFF4245),
  systemOrange: Color(0xFFFF9230),
  ansi: <Color>[
    Color(0xFF35424C),
    Color(0xFFB45648),
    Color(0xFF6CAA71),
    Color(0xFFC4AC62),
    Color(0xFF6D96B4),
    Color(0xFFBD7BCD),
    Color(0xFF7CCBCD),
    Color(0xFFDEE5EB),
    Color(0xFF465C6D),
    Color(0xFFDF6C5A),
    Color(0xFF79BE7E),
    Color(0xFFE5C872),
    Color(0xFF67B5ED),
    Color(0xFFD389E5),
    Color(0xFF84DDE0),
    Color(0xFFE5EFF5),
  ],
  ansiText: Color(0xFFE6E6E6),
  ansiCursor: Color(0xA8E6E6E6),
  ansiSelection: Color(0xFF334E5E),
  syntaxKeyword: Color(0xFFFF7AB2),
  syntaxString: Color(0xFFFF8170),
  syntaxNumber: Color(0xFFD9C97C),
  syntaxComment: Color(0xFF7F8C98),
  syntaxType: Color(0xFFACF2E4),
  syntaxLiteral: Color(0xFFB281EB),
  syntaxMeta: Color(0xFFFFA14F),
);
