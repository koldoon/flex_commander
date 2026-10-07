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

  /// Цвета, которые система выводит из акцента; `null` — спросить некого.
  ///
  /// Канала нет в тестах и на другой платформе, и это не ошибка: оформление
  /// остаётся с тем, что система даёт при синем акценте ([macOsBlueAccent],
  /// [MacOsTones.selection], [MacOsTones.textSelection]). Живые цвета приносит
  /// модуль `fc.systemAccent` (`docs/spec/macos-themes.md`, §5, §6а).
  final SystemAccentColors? accent;

  /// Акцент — кнопка подтверждения, обводка фокуса, ход работы.
  Color get _accent => accent?.accent ?? macOsBlueAccent;

  /// Выделенное в фокусе — курсор, активная плашка (§6а). **Не акцент:** у
  /// системы это свой цвет, темнее акцента и разный во внешностях.
  Color get _selection => accent?.selection ?? tones.selection;

  /// Чем писать поверх [fill].
  ///
  /// Система отдаёт белый всегда — все восемь её акцентов достаточно темны.
  /// Но «Другой…» в настройках даёт любой цвет, вплоть до почти белого, и белое
  /// по белому исчезает. Поэтому порог по яркости, а не «всегда белый»: это тот
  /// же ответ, что у системы, на всех её акцентах — и не тот же там, где она
  /// ошиблась бы.
  Color _on(Color fill) => fill.computeLuminance() > 0.5 ? tones.label : tones.onAccentText;

  Color get _onAccent => _on(_accent);

  Color get _onSelection => _on(_selection);

  @override
  Color get windowBackground => tones.windowBackground;

  // --- панель ---

  @override
  Color get panelBackground => tones.contentBackground;

  @override
  Color get panelBorder => tones.panelEdge;

  /// Разделитель — `separatorColor`, а не `gridColor`.
  ///
  /// Сетка таблицы и разделительная линия в AppKit разные роли, и на тёмной это
  /// видно: `gridColor` там `#1A1A1A`, то есть **темнее** и панели, и карточки —
  /// линия ушла бы в тень вместо того, чтобы делить. Разделитель обязан быть
  /// светлее того, что делит, и `separatorColor` полупрозрачно-белый именно
  /// затем. На светлой оба дают одно и то же `#E6E6E6`, поэтому там ничего не
  /// меняется.
  @override
  Color get columnDivider => tones.separator;

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
  Color get cursorBackground => _selection;

  @override
  Color get cursorText => _onSelection;

  /// Пометка — оранжевая, а не акцентная (`MacOsTones.systemOrange`).
  @override
  Color get markedBackground => tones.systemOrange.withValues(alpha: 0.16);

  @override
  Color get markedBar => tones.systemOrange;

  @override
  Color get icon => tones.secondaryLabel;

  @override
  Color get iconSelected => _onSelection;

  // --- плашка пути ---

  /// Плашка активной панели — **выделенное в фокусе**
  /// (`selectedContentBackgroundColor`), а пассивной — оно же без фокуса.
  ///
  /// Образец — выбранный сегмент переключателя: залит цветом системы и подписан
  /// белым, а невыбранный — нейтральной заливкой. До §6а здесь был сам акцент;
  /// у системы для выделенного свой цвет, темнее. Плашка показывает
  /// ровно то же самое — какая панель принимает клавиши, — и различать их
  /// оттенками серого мало: `unemphasizedSelection` и `controlColor` на тёмной
  /// внешности сходятся так близко, что различие пропадает вовсе.
  @override
  Color get pathBackground => _selection;

  @override
  Color get pathBorder => tones.separator;

  @override
  Color get pathText => _onSelection;

  /// Крошки приглушаются **подписью плашки**, а не подписью списка: на цветной
  /// заливке приглушать надо то, чем по ней пишут.
  @override
  Color get pathSecondaryText => _onSelection.withValues(alpha: 0.65);

  /// Пассивная — «выделенное, но не в фокусе»: та самая пара AppKit, вторая
  /// половина которой теперь досталась акценту.
  @override
  Color get pathInactiveBackground => tones.unemphasizedSelection;

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

  /// Выделение текста — `selectedTextBackgroundColor`, непрозрачный, как у
  /// системы (§6а). До того был акцент с прозрачностью по рецепту Xcode; у
  /// системы для этого готовый цвет, и он идёт ещё и за настройкой «Цвет
  /// выделения».
  @override
  Color get inputSelection => accent?.textSelection ?? tones.textSelection;

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

  /// Сняты с `NSProgressIndicator`: чёрный 5% в светлой, белый 10% в тёмной
  /// (`spec/progress-bar.md`, §2).
  @override
  Color get progressTrack => tones.brightness == Brightness.dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000);

  @override
  Color get error => tones.systemRed;
}
