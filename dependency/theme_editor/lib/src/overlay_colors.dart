import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Цвета поверх темы: своё там, где задано, чужое во всём остальном.
///
/// **Делегирование руками, а не карта ролей.** Полсотни однострочных геттеров
/// скучны, но роли за нас считает компилятор: добавили роль в [FcColors] —
/// накладка перестала собираться. Карта `Color role(String name)` эту проверку
/// теряет ровно там, где оформление труднее всего удержать в порядке
/// (`docs/spec/theme-editor.md`, §5).
///
/// **Производная роль своего источника не догоняет.** `focusRing` у темы
/// выведен из `inputBorder`, но берётся он у [base] — значит, поправленная
/// обводка поля сама по себе рамку фокуса не перекрасит. Так и задумано: иначе
/// накладке пришлось бы знать, вывела тема эту роль или назвала её своей, а
/// спросить об этом её нечем. В окне обе роли стоят рядом и правятся порознь.
class OverlayColors implements FcColors {
  /// Цвета терминала собираются сразу, а не при каждом чтении: список
  /// спрашивают на каждую строку вывода, и складывать его там заново значило бы
  /// делать это тысячи раз в секунду.
  OverlayColors(this.base, this.overrides)
    : terminalAnsi = [for (final (index, color) in base.terminalAnsi.indexed) overrides[ansiRole(index)] ?? color];

  final FcColors base;

  /// Роль → своё значение; чего здесь нет, берётся у [base].
  final Map<String, Color> overrides;

  /// Шестнадцать цветов ANSI: у них не роль, а **номер**, и в накладке они
  /// лежат ролями `terminalAnsi0`…`terminalAnsi15` — иначе список пришлось бы
  /// хранить вторым способом рядом с картой (`docs/spec/theme-editor.md`, §7).
  @override
  final List<Color> terminalAnsi;

  /// Имя роли у цвета ANSI с этим номером.
  static String ansiRole(int index) => 'terminalAnsi$index';

  @override
  Color get windowBackground => overrides['windowBackground'] ?? base.windowBackground;

  @override
  Color get panelBackground => overrides['panelBackground'] ?? base.panelBackground;

  @override
  Color get panelBorder => overrides['panelBorder'] ?? base.panelBorder;

  @override
  Color get columnDivider => overrides['columnDivider'] ?? base.columnDivider;

  @override
  Color get rowText => overrides['rowText'] ?? base.rowText;

  @override
  Color get directoryText => overrides['directoryText'] ?? base.directoryText;

  @override
  Color get sizeText => overrides['sizeText'] ?? base.sizeText;

  @override
  Color get secondaryText => overrides['secondaryText'] ?? base.secondaryText;

  @override
  Color get headerText => overrides['headerText'] ?? base.headerText;

  @override
  Color get cursorBackground => overrides['cursorBackground'] ?? base.cursorBackground;

  @override
  Color get cursorText => overrides['cursorText'] ?? base.cursorText;

  @override
  Color get markedBackground => overrides['markedBackground'] ?? base.markedBackground;

  @override
  Color get markedBar => overrides['markedBar'] ?? base.markedBar;

  @override
  Color get icon => overrides['icon'] ?? base.icon;

  @override
  Color get iconSelected => overrides['iconSelected'] ?? base.iconSelected;

  @override
  Color get pathBackground => overrides['pathBackground'] ?? base.pathBackground;

  @override
  Color get pathBorder => overrides['pathBorder'] ?? base.pathBorder;

  @override
  Color get pathText => overrides['pathText'] ?? base.pathText;

  @override
  Color get pathInactiveBackground => overrides['pathInactiveBackground'] ?? base.pathInactiveBackground;

  @override
  Color get pathInactiveText => overrides['pathInactiveText'] ?? base.pathInactiveText;

  @override
  Color get functionButtonBackground => overrides['functionButtonBackground'] ?? base.functionButtonBackground;

  @override
  Color get functionButtonText => overrides['functionButtonText'] ?? base.functionButtonText;

  @override
  Color get functionKeyNumber => overrides['functionKeyNumber'] ?? base.functionKeyNumber;

  @override
  Color get dialogBackground => overrides['dialogBackground'] ?? base.dialogBackground;

  @override
  Color get dialogTitleBackground => overrides['dialogTitleBackground'] ?? base.dialogTitleBackground;

  @override
  Color get dialogTitleText => overrides['dialogTitleText'] ?? base.dialogTitleText;

  @override
  Color get dialogLabel => overrides['dialogLabel'] ?? base.dialogLabel;

  @override
  Color get dialogText => overrides['dialogText'] ?? base.dialogText;

  @override
  Color get dialogBarrier => overrides['dialogBarrier'] ?? base.dialogBarrier;

  @override
  Color get dialogListBackground => overrides['dialogListBackground'] ?? base.dialogListBackground;

  @override
  Color get dialogListBorder => overrides['dialogListBorder'] ?? base.dialogListBorder;

  @override
  Color get buttonBackground => overrides['buttonBackground'] ?? base.buttonBackground;

  @override
  Color get buttonPrimaryBackground => overrides['buttonPrimaryBackground'] ?? base.buttonPrimaryBackground;

  @override
  Color get buttonText => overrides['buttonText'] ?? base.buttonText;

  @override
  Color get buttonBorder => overrides['buttonBorder'] ?? base.buttonBorder;

  @override
  Color get buttonPressed => overrides['buttonPressed'] ?? base.buttonPressed;

  @override
  Color get inputBackground => overrides['inputBackground'] ?? base.inputBackground;

  @override
  Color get inputBorder => overrides['inputBorder'] ?? base.inputBorder;

  @override
  Color get inputText => overrides['inputText'] ?? base.inputText;

  @override
  Color get inputHint => overrides['inputHint'] ?? base.inputHint;

  @override
  Color get inputSelection => overrides['inputSelection'] ?? base.inputSelection;

  @override
  Color get focusRing => overrides['focusRing'] ?? base.focusRing;

  @override
  Color get shadow => overrides['shadow'] ?? base.shadow;

  @override
  Color get iconShadow => overrides['iconShadow'] ?? base.iconShadow;

  @override
  Color get syntaxKeyword => overrides['syntaxKeyword'] ?? base.syntaxKeyword;

  @override
  Color get syntaxString => overrides['syntaxString'] ?? base.syntaxString;

  @override
  Color get syntaxNumber => overrides['syntaxNumber'] ?? base.syntaxNumber;

  @override
  Color get syntaxComment => overrides['syntaxComment'] ?? base.syntaxComment;

  @override
  Color get syntaxType => overrides['syntaxType'] ?? base.syntaxType;

  @override
  Color get syntaxLiteral => overrides['syntaxLiteral'] ?? base.syntaxLiteral;

  @override
  Color get syntaxMeta => overrides['syntaxMeta'] ?? base.syntaxMeta;

  @override
  Color get terminalText => overrides['terminalText'] ?? base.terminalText;

  @override
  Color get terminalCursor => overrides['terminalCursor'] ?? base.terminalCursor;

  @override
  Color get terminalSelection => overrides['terminalSelection'] ?? base.terminalSelection;

  @override
  Color get progress => overrides['progress'] ?? base.progress;

  @override
  Color get error => overrides['error'] ?? base.error;
}
