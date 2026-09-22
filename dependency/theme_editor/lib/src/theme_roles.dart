import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Каталог ролей оформления: что есть в теме и в каком разделе это правят.
///
/// Компилятор такой список не считает — он проверяет накладку
/// ([OverlayColors]), а не каталог. Поэтому за полнотой следит доктринальный
/// тест: каталог перечисляет ровно те роли, что объявлены в контракте, и в тех
/// же группах (`docs/spec/theme-editor.md`, §7).

/// Род метрики: им заданы пределы.
///
/// Родом, а не парой чисел у каждой роли: придумывать `min`/`max` каждой из 93
/// метрик значило бы завести 186 чисел, которые никто не выверит
/// (`docs/spec/theme-editor.md`, §8).
enum MetricKind {
  /// Высоты, ширины, отступы окон: `rowHeight`, `dialogMaxWidth`, `iconSize`.
  ///
  /// Верх с запасом: самая большая мера темы — `dialogMaxWidth`, 800, и предел
  /// ниже неё не дал бы вернуть умолчание набором.
  size(0, 2000),

  /// Просветы и поля: `dialogGap`, `columnGap`, `panelTopPadding`.
  gap(0, 200),

  /// Скругления: `dialogRadius`, `inputRadius`.
  radius(0, 100),

  /// Толщины линий: `strokeWidth`, `caretWidth`, `markedBarWidth`.
  ///
  /// Нуль законен — линейку убирают.
  thickness(0, 20),

  /// Доли: `dialogWidthFactor`, `settingsWidthFactor`.
  ///
  /// Нуля нет: окно нулевой ширины не закрыть и не разглядеть.
  fraction(0.05, 1),

  /// Кегль: `fontSize`, `sectionHeadingFontSize`.
  ///
  /// Нуля нет по той же причине: приложение обязано остаться управляемым.
  fontSize(6, 72);

  const MetricKind(this.min, this.max);

  final double min;
  final double max;
}

/// Цвет темы: имя роли, раздел окна и как прочесть её значение.
class ColorRole {
  const ColorRole(this.name, this.section, this.read);

  /// Имя роли в контракте — оно же ключ в накладке и в файле настроек.
  final String name;

  /// Заголовок раздела редактора.
  final String section;

  /// Замыканием, а не по имени: так роль берётся у темы тем же способом, что и
  /// у всех прочих, и ошибку в ней ловит компилятор.
  final Color Function(FcColors colors) read;
}

/// Размер темы: то же самое плюс род, из которого берутся пределы.
class MetricRole {
  const MetricRole(this.name, this.section, this.kind, this.read);

  final String name;
  final String section;
  final MetricKind kind;
  final double Function(FcMetrics metrics) read;
}

/// Группа контракта → раздел окна.
///
/// Группы в контракте названы по-русски и комментарием (`// --- панель ---`), а
/// раздел окна — по-английски: английский текст это ключ перевода. Сверяет их
/// доктринальный тест, поэтому карта общая на оба и лежит здесь, а не в нём.
///
/// Пустой ключ — то, что в контракте стоит до первой группы.
const Map<String, String> colorSections = {
  '': 'Window',
  'панель': 'Panel',
  'список файлов': 'File list',
  'плашка пути': 'Path plate',
  'нижняя панель': 'Function keys',
  'окна команд': 'Dialogs',
  'кнопки окна команды': 'Dialog buttons',
  'поле ввода': 'Input',
  'подсветка синтаксиса': 'Syntax',
  'терминал': 'Terminal',
  'прочее': 'Other',
};

/// То же для размеров. Разделы у них свои, а не общие с цветами: иначе в одном
/// разделе стояли бы полсотни полей о цвете панели и её же размерах, и
/// оглавление перестало бы помогать.
const Map<String, String> metricSections = {
  'окно (Main.mxml)': 'Window sizes',
  'панель (FilesPanel.mxml)': 'Panel sizes',
  'нижняя панель (FunctionKeyRenderer)': 'Function key sizes',
  'окна команд (TitledPopupPanelSkin)': 'Dialog sizes',
  'всплывающее сообщение': 'Toast sizes',
  'кнопка окна команды (RegularButtonSkin)': 'Dialog button sizes',
  'поле ввода (TextInputBorderedSkin)': 'Input sizes',
  'полоса хода работы (ProgressBar.mxml)': 'Progress bar sizes',
  'общее': 'Common sizes',
};

/// Раздел шрифтов: он один, и группы в контракте у него нет.
const String fontSection = 'Fonts';

/// Цвета: роль, раздел и как прочесть её у темы.
///
/// Шестнадцать цветов ANSI стоят тут по одному: в контракте они списком, потому
/// что у них номер, а не роль, — но правят их поодиночке, и накладка держит их
/// ролями `terminalAnsi0`…`terminalAnsi15` ([OverlayColors.ansiRole]).
///
/// `final`, а не `const`: значение роли читается замыканием, а замыкание в
/// Dart константой не бывает.
final List<ColorRole> colorRoles = [
  ColorRole('windowBackground', 'Window', (colors) => colors.windowBackground),
  ColorRole('panelBackground', 'Panel', (colors) => colors.panelBackground),
  ColorRole('panelBorder', 'Panel', (colors) => colors.panelBorder),
  ColorRole('columnDivider', 'Panel', (colors) => colors.columnDivider),
  ColorRole('rowText', 'File list', (colors) => colors.rowText),
  ColorRole('directoryText', 'File list', (colors) => colors.directoryText),
  ColorRole('sizeText', 'File list', (colors) => colors.sizeText),
  ColorRole('secondaryText', 'File list', (colors) => colors.secondaryText),
  ColorRole('headerText', 'File list', (colors) => colors.headerText),
  ColorRole('cursorBackground', 'File list', (colors) => colors.cursorBackground),
  ColorRole('cursorText', 'File list', (colors) => colors.cursorText),
  ColorRole('markedBackground', 'File list', (colors) => colors.markedBackground),
  ColorRole('markedBar', 'File list', (colors) => colors.markedBar),
  ColorRole('icon', 'File list', (colors) => colors.icon),
  ColorRole('iconSelected', 'File list', (colors) => colors.iconSelected),
  ColorRole('pathBackground', 'Path plate', (colors) => colors.pathBackground),
  ColorRole('pathBorder', 'Path plate', (colors) => colors.pathBorder),
  ColorRole('pathText', 'Path plate', (colors) => colors.pathText),
  ColorRole('pathInactiveBackground', 'Path plate', (colors) => colors.pathInactiveBackground),
  ColorRole('pathInactiveText', 'Path plate', (colors) => colors.pathInactiveText),
  ColorRole('functionButtonBackground', 'Function keys', (colors) => colors.functionButtonBackground),
  ColorRole('functionButtonText', 'Function keys', (colors) => colors.functionButtonText),
  ColorRole('functionKeyNumber', 'Function keys', (colors) => colors.functionKeyNumber),
  ColorRole('dialogBackground', 'Dialogs', (colors) => colors.dialogBackground),
  ColorRole('dialogTitleBackground', 'Dialogs', (colors) => colors.dialogTitleBackground),
  ColorRole('dialogTitleText', 'Dialogs', (colors) => colors.dialogTitleText),
  ColorRole('dialogLabel', 'Dialogs', (colors) => colors.dialogLabel),
  ColorRole('dialogText', 'Dialogs', (colors) => colors.dialogText),
  ColorRole('dialogBarrier', 'Dialogs', (colors) => colors.dialogBarrier),
  ColorRole('dialogListBackground', 'Dialogs', (colors) => colors.dialogListBackground),
  ColorRole('dialogListBorder', 'Dialogs', (colors) => colors.dialogListBorder),
  ColorRole('buttonBackground', 'Dialog buttons', (colors) => colors.buttonBackground),
  ColorRole('buttonPrimaryBackground', 'Dialog buttons', (colors) => colors.buttonPrimaryBackground),
  ColorRole('buttonText', 'Dialog buttons', (colors) => colors.buttonText),
  ColorRole('buttonBorder', 'Dialog buttons', (colors) => colors.buttonBorder),
  ColorRole('buttonPressed', 'Dialog buttons', (colors) => colors.buttonPressed),
  ColorRole('inputBackground', 'Input', (colors) => colors.inputBackground),
  ColorRole('inputBorder', 'Input', (colors) => colors.inputBorder),
  ColorRole('inputText', 'Input', (colors) => colors.inputText),
  ColorRole('inputHint', 'Input', (colors) => colors.inputHint),
  ColorRole('inputSelection', 'Input', (colors) => colors.inputSelection),
  ColorRole('focusRing', 'Input', (colors) => colors.focusRing),
  ColorRole('shadow', 'Input', (colors) => colors.shadow),
  ColorRole('iconShadow', 'Input', (colors) => colors.iconShadow),
  ColorRole('syntaxKeyword', 'Syntax', (colors) => colors.syntaxKeyword),
  ColorRole('syntaxString', 'Syntax', (colors) => colors.syntaxString),
  ColorRole('syntaxNumber', 'Syntax', (colors) => colors.syntaxNumber),
  ColorRole('syntaxComment', 'Syntax', (colors) => colors.syntaxComment),
  ColorRole('syntaxType', 'Syntax', (colors) => colors.syntaxType),
  ColorRole('syntaxLiteral', 'Syntax', (colors) => colors.syntaxLiteral),
  ColorRole('syntaxMeta', 'Syntax', (colors) => colors.syntaxMeta),
  ColorRole('terminalText', 'Terminal', (colors) => colors.terminalText),
  ColorRole('terminalCursor', 'Terminal', (colors) => colors.terminalCursor),
  ColorRole('terminalSelection', 'Terminal', (colors) => colors.terminalSelection),
  ColorRole('terminalAnsi0', 'Terminal', (colors) => colors.terminalAnsi[0]),
  ColorRole('terminalAnsi1', 'Terminal', (colors) => colors.terminalAnsi[1]),
  ColorRole('terminalAnsi2', 'Terminal', (colors) => colors.terminalAnsi[2]),
  ColorRole('terminalAnsi3', 'Terminal', (colors) => colors.terminalAnsi[3]),
  ColorRole('terminalAnsi4', 'Terminal', (colors) => colors.terminalAnsi[4]),
  ColorRole('terminalAnsi5', 'Terminal', (colors) => colors.terminalAnsi[5]),
  ColorRole('terminalAnsi6', 'Terminal', (colors) => colors.terminalAnsi[6]),
  ColorRole('terminalAnsi7', 'Terminal', (colors) => colors.terminalAnsi[7]),
  ColorRole('terminalAnsi8', 'Terminal', (colors) => colors.terminalAnsi[8]),
  ColorRole('terminalAnsi9', 'Terminal', (colors) => colors.terminalAnsi[9]),
  ColorRole('terminalAnsi10', 'Terminal', (colors) => colors.terminalAnsi[10]),
  ColorRole('terminalAnsi11', 'Terminal', (colors) => colors.terminalAnsi[11]),
  ColorRole('terminalAnsi12', 'Terminal', (colors) => colors.terminalAnsi[12]),
  ColorRole('terminalAnsi13', 'Terminal', (colors) => colors.terminalAnsi[13]),
  ColorRole('terminalAnsi14', 'Terminal', (colors) => colors.terminalAnsi[14]),
  ColorRole('terminalAnsi15', 'Terminal', (colors) => colors.terminalAnsi[15]),
  ColorRole('progress', 'Other', (colors) => colors.progress),
  ColorRole('error', 'Other', (colors) => colors.error),
];

/// Размеры: роль, раздел, род (он же пределы) и как прочесть её у темы.
final List<MetricRole> metricRoles = [
  MetricRole('windowTitleBarHeight', 'Window sizes', MetricKind.size, (metrics) => metrics.windowTitleBarHeight),
  MetricRole('windowControlsWidth', 'Window sizes', MetricKind.size, (metrics) => metrics.windowControlsWidth),
  MetricRole('windowDragHandleWidth', 'Window sizes', MetricKind.size, (metrics) => metrics.windowDragHandleWidth),
  MetricRole(
    'windowTitleBarContentNudge',
    'Window sizes',
    MetricKind.gap,
    (metrics) => metrics.windowTitleBarContentNudge,
  ),
  MetricRole('windowTopPadding', 'Window sizes', MetricKind.gap, (metrics) => metrics.windowTopPadding),
  MetricRole('windowSidePadding', 'Window sizes', MetricKind.gap, (metrics) => metrics.windowSidePadding),
  MetricRole('areaGap', 'Window sizes', MetricKind.gap, (metrics) => metrics.areaGap),
  MetricRole('windowBottomPadding', 'Window sizes', MetricKind.gap, (metrics) => metrics.windowBottomPadding),
  MetricRole('pathHeaderHeight', 'Panel sizes', MetricKind.size, (metrics) => metrics.pathHeaderHeight),
  MetricRole('pathHeaderRadius', 'Panel sizes', MetricKind.radius, (metrics) => metrics.pathHeaderRadius),
  MetricRole('pathHeaderMinInset', 'Panel sizes', MetricKind.size, (metrics) => metrics.pathHeaderMinInset),
  MetricRole('panelRadius', 'Panel sizes', MetricKind.radius, (metrics) => metrics.panelRadius),
  MetricRole('panelTopPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.panelTopPadding),
  MetricRole('headerRowHeight', 'Panel sizes', MetricKind.size, (metrics) => metrics.headerRowHeight),
  MetricRole('rowHeight', 'Panel sizes', MetricKind.size, (metrics) => metrics.rowHeight),
  MetricRole('rowGap', 'Panel sizes', MetricKind.gap, (metrics) => metrics.rowGap),
  MetricRole('statusBarHeight', 'Panel sizes', MetricKind.size, (metrics) => metrics.statusBarHeight),
  MetricRole('panelLeftPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.panelLeftPadding),
  MetricRole('panelRightPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.panelRightPadding),
  MetricRole('labelPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.labelPadding),
  MetricRole('columnGap', 'Panel sizes', MetricKind.gap, (metrics) => metrics.columnGap),
  MetricRole('markedBarWidth', 'Panel sizes', MetricKind.thickness, (metrics) => metrics.markedBarWidth),
  MetricRole('tileGap', 'Panel sizes', MetricKind.gap, (metrics) => metrics.tileGap),
  MetricRole('nameBottomPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.nameBottomPadding),
  MetricRole('iconLeftPadding', 'Panel sizes', MetricKind.gap, (metrics) => metrics.iconLeftPadding),
  MetricRole('iconGap', 'Panel sizes', MetricKind.gap, (metrics) => metrics.iconGap),
  MetricRole('iconColumnWidth', 'Panel sizes', MetricKind.size, (metrics) => metrics.iconColumnWidth),
  MetricRole('treeMarkGap', 'Panel sizes', MetricKind.gap, (metrics) => metrics.treeMarkGap),
  MetricRole('functionButtonHeight', 'Function key sizes', MetricKind.size, (metrics) => metrics.functionButtonHeight),
  MetricRole(
    'functionButtonRadius',
    'Function key sizes',
    MetricKind.radius,
    (metrics) => metrics.functionButtonRadius,
  ),
  MetricRole(
    'functionKeyNumberWidth',
    'Function key sizes',
    MetricKind.size,
    (metrics) => metrics.functionKeyNumberWidth,
  ),
  MetricRole('functionKeyNumberGap', 'Function key sizes', MetricKind.gap, (metrics) => metrics.functionKeyNumberGap),
  MetricRole('functionButtonGap', 'Function key sizes', MetricKind.gap, (metrics) => metrics.functionButtonGap),
  MetricRole('functionBarSideOutset', 'Function key sizes', MetricKind.gap, (metrics) => metrics.functionBarSideOutset),
  MetricRole(
    'functionBarRightPadding',
    'Function key sizes',
    MetricKind.gap,
    (metrics) => metrics.functionBarRightPadding,
  ),
  MetricRole('dialogRadius', 'Dialog sizes', MetricKind.radius, (metrics) => metrics.dialogRadius),
  MetricRole('dialogWidthFactor', 'Dialog sizes', MetricKind.fraction, (metrics) => metrics.dialogWidthFactor),
  MetricRole('paletteWidthFactor', 'Dialog sizes', MetricKind.fraction, (metrics) => metrics.paletteWidthFactor),
  MetricRole('dialogMinWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogMinWidth),
  MetricRole('dialogMaxWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogMaxWidth),
  MetricRole('dialogMinHeight', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogMinHeight),
  MetricRole('dialogResizeEdge', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogResizeEdge),
  MetricRole('dialogTitleHeight', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogTitleHeight),
  MetricRole('dialogPadding', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogPadding),
  MetricRole('dialogHorizontalPadding', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogHorizontalPadding),
  MetricRole('dialogContentTopPadding', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogContentTopPadding),
  MetricRole('dialogGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogGap),
  MetricRole('dialogLineGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogLineGap),
  MetricRole('dialogWideRowGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogWideRowGap),
  MetricRole('dialogSectionGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogSectionGap),
  MetricRole('settingsWidthFactor', 'Dialog sizes', MetricKind.fraction, (metrics) => metrics.settingsWidthFactor),
  MetricRole(
    'sectionHeadingFontSize',
    'Dialog sizes',
    MetricKind.fontSize,
    (metrics) => metrics.sectionHeadingFontSize,
  ),
  MetricRole('settingsTocWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.settingsTocWidth),
  MetricRole('sectionEntryGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.sectionEntryGap),
  MetricRole('sectionGap', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.sectionGap),
  MetricRole('dialogLabelWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogLabelWidth),
  MetricRole('dialogLabelMaxWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogLabelMaxWidth),
  MetricRole('helpCellMaxWidth', 'Dialog sizes', MetricKind.size, (metrics) => metrics.helpCellMaxWidth),
  MetricRole('dialogTopInset', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogTopInset),
  MetricRole('dialogScreenInset', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogScreenInset),
  MetricRole('dialogAreaInset', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogAreaInset),
  MetricRole('dialogMaxScreenFactor', 'Dialog sizes', MetricKind.fraction, (metrics) => metrics.dialogMaxScreenFactor),
  MetricRole('dialogDragKeepVisible', 'Dialog sizes', MetricKind.size, (metrics) => metrics.dialogDragKeepVisible),
  MetricRole('dialogShadowOffset', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogShadowOffset),
  MetricRole('dialogShadowBlur', 'Dialog sizes', MetricKind.gap, (metrics) => metrics.dialogShadowBlur),
  MetricRole('toastPadding', 'Toast sizes', MetricKind.gap, (metrics) => metrics.toastPadding),
  MetricRole('toastHorizontalPadding', 'Toast sizes', MetricKind.gap, (metrics) => metrics.toastHorizontalPadding),
  MetricRole('toastBottomOffset', 'Toast sizes', MetricKind.gap, (metrics) => metrics.toastBottomOffset),
  MetricRole('buttonHeight', 'Dialog button sizes', MetricKind.size, (metrics) => metrics.buttonHeight),
  MetricRole('buttonRadius', 'Dialog button sizes', MetricKind.radius, (metrics) => metrics.buttonRadius),
  MetricRole(
    'buttonHorizontalPadding',
    'Dialog button sizes',
    MetricKind.gap,
    (metrics) => metrics.buttonHorizontalPadding,
  ),
  MetricRole('buttonShadowOffset', 'Dialog button sizes', MetricKind.gap, (metrics) => metrics.buttonShadowOffset),
  MetricRole('buttonShadowBlur', 'Dialog button sizes', MetricKind.gap, (metrics) => metrics.buttonShadowBlur),
  MetricRole('checkboxSize', 'Input sizes', MetricKind.size, (metrics) => metrics.checkboxSize),
  MetricRole('checkboxGap', 'Input sizes', MetricKind.gap, (metrics) => metrics.checkboxGap),
  MetricRole('inputHeight', 'Input sizes', MetricKind.size, (metrics) => metrics.inputHeight),
  MetricRole('inputRadius', 'Input sizes', MetricKind.radius, (metrics) => metrics.inputRadius),
  MetricRole('inputHorizontalPadding', 'Input sizes', MetricKind.gap, (metrics) => metrics.inputHorizontalPadding),
  MetricRole('commandLineHeight', 'Input sizes', MetricKind.size, (metrics) => metrics.commandLineHeight),
  MetricRole('progressHeight', 'Progress bar sizes', MetricKind.size, (metrics) => metrics.progressHeight),
  MetricRole('progressInset', 'Progress bar sizes', MetricKind.thickness, (metrics) => metrics.progressInset),
  MetricRole('scrollbarInset', 'Common sizes', MetricKind.thickness, (metrics) => metrics.scrollbarInset),
  MetricRole('strokeWidth', 'Common sizes', MetricKind.thickness, (metrics) => metrics.strokeWidth),
  MetricRole('focusRingWidth', 'Common sizes', MetricKind.thickness, (metrics) => metrics.focusRingWidth),
  MetricRole('caretWidth', 'Common sizes', MetricKind.thickness, (metrics) => metrics.caretWidth),
  MetricRole('caretRadius', 'Common sizes', MetricKind.radius, (metrics) => metrics.caretRadius),
  MetricRole('fontSize', 'Common sizes', MetricKind.fontSize, (metrics) => metrics.fontSize),
  MetricRole('fontCapInset', 'Common sizes', MetricKind.gap, (metrics) => metrics.fontCapInset),
  MetricRole('iconSize', 'Common sizes', MetricKind.size, (metrics) => metrics.iconSize),
  MetricRole('cellPadding', 'Common sizes', MetricKind.gap, (metrics) => metrics.cellPadding),
  MetricRole('rowContentVerticalNudge', 'Common sizes', MetricKind.gap, (metrics) => metrics.rowContentVerticalNudge),
  MetricRole('rowTextVerticalNudge', 'Common sizes', MetricKind.gap, (metrics) => metrics.rowTextVerticalNudge),
  MetricRole('resizeHandleWidth', 'Common sizes', MetricKind.size, (metrics) => metrics.resizeHandleWidth),
  MetricRole('minPanelWidth', 'Common sizes', MetricKind.size, (metrics) => metrics.minPanelWidth),
];
