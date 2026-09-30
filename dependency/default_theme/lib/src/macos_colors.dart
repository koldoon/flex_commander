import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'macos_palette.dart';

/// Роли оформления, положенные на семантику macOS.
///
/// Отображение **одно** на две внешности, а тона — двое ([macOsLightTones] и
/// [macOsDarkTones]). Не два класса по пятьдесят восемь геттеров: продублировав
/// отображение, мы получили бы два места, где «панель — это фон таблицы», и
/// рано или поздно они разошлись бы. Различие светлого и тёмного — это различие
/// **значений**, и жить оно должно в значениях.
///
/// Наследуется от [FcColors], **а не от `DefaultColors`**, хотя контракт и
/// советует второе. Причина одна и весомая: от референсной темы забытая роль
/// досталась бы молча — и осталась бы тёмно-синей посреди светлого окна, о чём
/// никто бы не узнал. От контракта забытую роль требует компилятор. Четыре роли
/// с умолчанием (`dialogListBackground`, `dialogListBorder`, `focusRing`,
/// `iconShadow`) он не потребует — их сторожит тест на полноту.
class MacOsColors extends FcColors {
  const MacOsColors({required this.tones, this.accent});

  /// Светлые тона или тёмные.
  final MacOsTones tones;

  /// Акцент, выбранный в системе; `null` — спросить некого.
  ///
  /// Канала нет в тестах и на другой платформе, и это не ошибка: оформление
  /// остаётся с [macOsBlueAccent]. Живой акцент приносит модуль
  /// `fc.systemAccent` (`docs/spec/macos-themes.md`, §5).
  final Color? accent;

  Color get _accent => accent ?? macOsBlueAccent;

  /// Чем писать поверх акцента.
  ///
  /// Система отдаёт белый всегда — все восемь её акцентов достаточно темны.
  /// Но «Другой…» в настройках даёт любой цвет, вплоть до почти белого, и белое
  /// по белому исчезает. Поэтому порог по яркости, а не «всегда белый»: это тот
  /// же ответ, что у системы, на всех её акцентах — и не тот же там, где она
  /// ошиблась бы.
  Color get _onAccent => _accent.computeLuminance() > 0.5 ? tones.label : tones.onAccentText;

  @override
  Color get windowBackground => tones.windowBackground;

  // --- панель ---

  @override
  Color get panelBackground => tones.contentBackground;

  @override
  Color get panelBorder => tones.separator;

  @override
  Color get columnDivider => tones.grid;

  // --- список файлов ---

  @override
  Color get rowText => tones.label;

  @override
  Color get directoryText => tones.label;

  /// Размер — подпись поменьше важностью, и это **расхождение с референсом**,
  /// где вся строка одного цвета. Иерархия подписей — правило macOS, и без неё
  /// строка на светлом фоне читается кашей.
  @override
  Color get sizeText => tones.secondaryLabel;

  @override
  Color get secondaryText => tones.secondaryLabel;

  @override
  Color get headerText => tones.headerText;

  @override
  Color get cursorBackground => _accent;

  @override
  Color get cursorText => _onAccent;

  /// Пометка — оранжевая, а не акцентная (`MacOsTones.systemOrange`).
  @override
  Color get markedBackground => tones.systemOrange.withValues(alpha: 0.16);

  @override
  Color get markedBar => tones.systemOrange;

  @override
  Color get icon => tones.secondaryLabel;

  @override
  Color get iconSelected => _onAccent;

  // --- плашка пути ---

  /// Активная плашка — выделенное не в фокусе, пассивная — лицо элемента
  /// управления. Пара `emphasized`/`unemphasized` у AppKit готовая, и показывает
  /// она ровно то, что показывает плашка: какая панель принимает клавиши.
  @override
  Color get pathBackground => tones.unemphasizedSelection;

  @override
  Color get pathBorder => tones.separator;

  @override
  Color get pathText => tones.label;

  @override
  Color get pathInactiveBackground => tones.control;

  @override
  Color get pathInactiveText => tones.secondaryLabel;

  // --- нижняя панель ---

  @override
  Color get functionButtonBackground => tones.control;

  @override
  Color get functionButtonText => tones.controlText;

  /// Номер клавиши — подсказка, слово — действие; в референсе оба одного цвета.
  @override
  Color get functionKeyNumber => tones.secondaryLabel;

  // --- окна команд ---

  @override
  Color get dialogBackground => tones.windowBackground;

  @override
  Color get dialogTitleBackground => tones.control;

  @override
  Color get dialogTitleText => tones.label;

  @override
  Color get dialogLabel => tones.label;

  @override
  Color get dialogText => tones.secondaryLabel;

  @override
  Color get dialogBarrier => tones.scrim;

  /// Карточка раздела и список находок — **своя поверхность**, а не панельная.
  ///
  /// Контракт разводит эти роли нарочно, и на живом приложении стало видно,
  /// почему: карточка встаёт и в окне команды, и прямо на панели — сведения об
  /// объекте показываются полноэкранным просмотром. Возьми она фон содержимого,
  /// и на панели, у которой фон тот же, она пропала бы вовсе.
  @override
  Color get dialogListBackground => tones.card;

  @override
  Color get dialogListBorder => tones.cardEdge;

  // --- кнопки окна команды ---

  @override
  Color get buttonBackground => tones.control;

  @override
  Color get buttonPrimaryBackground => _accent;

  @override
  Color get buttonText => tones.controlText;

  @override
  Color get buttonPrimaryText => _onAccent;

  @override
  Color get buttonBorder => tones.controlEdge;

  @override
  Color get buttonPressed => tones.pressed;

  // --- поле ввода ---

  @override
  Color get inputBackground => tones.contentBackground;

  @override
  Color get inputBorder => tones.separator;

  /// Набираемый текст — `textColor`, а не `labelColor`: в AppKit он непрозрачен.
  @override
  Color get inputText => tones.text;

  @override
  Color get inputHint => tones.placeholder;

  /// Выделение в поле — акцент с прозрачностью.
  ///
  /// Вес не выдуман: `DVTSourceTextSelectionColor` темы Xcode «Default (Light)»
  /// равен `#A4CDFF`, а это в точности акцент «Blue» при альфе около 0.3 над
  /// белым. Рецепт, стало быть, тоже Apple, и проверяется арифметикой.
  @override
  Color get inputSelection => _accent.withValues(alpha: tones.brightness == Brightness.light ? 0.3 : 0.45);

  /// Обводка фокуса — акцент вполсилы, как `keyboardFocusIndicatorColor`.
  @override
  Color get focusRing => _accent.withValues(alpha: 0.5);

  @override
  Color get shadow => tones.shadow;

  @override
  Color get controlShadow => tones.controlShadow;

  /// Тень под миниатюрой — чёрный 45 %, как у референса, и менять её незачем:
  /// это значение замерено с собственного значка macOS
  /// (`docs/spec/file-thumbnails.md`, §9), то есть уже системное.
  @override
  Color get iconShadow => const Color(0x73000000);

  // --- подсветка синтаксиса ---

  @override
  Color get syntaxKeyword => tones.syntaxKeyword;

  @override
  Color get syntaxString => tones.syntaxString;

  @override
  Color get syntaxNumber => tones.syntaxNumber;

  @override
  Color get syntaxComment => tones.syntaxComment;

  @override
  Color get syntaxType => tones.syntaxType;

  @override
  Color get syntaxLiteral => tones.syntaxLiteral;

  @override
  Color get syntaxMeta => tones.syntaxMeta;

  // --- терминал ---

  @override
  List<Color> get terminalAnsi => tones.ansi;

  @override
  Color get terminalText => tones.ansiText;

  @override
  Color get terminalCursor => tones.ansiCursor;

  @override
  Color get terminalSelection => tones.ansiSelection;

  // --- прочее ---

  @override
  Color get progress => _accent;

  @override
  Color get error => tones.systemRed;
}
