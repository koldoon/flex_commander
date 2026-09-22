import 'package:fc_ui_api/fc_ui_api.dart';

/// Размеры поверх темы — тем же способом, что и цвета ([OverlayColors]).
class OverlayMetrics implements FcMetrics {
  const OverlayMetrics(this.base, this.overrides);

  final FcMetrics base;

  /// Роль → своё значение; чего здесь нет, берётся у [base].
  final Map<String, double> overrides;

  @override
  double get windowTitleBarHeight => overrides['windowTitleBarHeight'] ?? base.windowTitleBarHeight;

  @override
  double get windowControlsWidth => overrides['windowControlsWidth'] ?? base.windowControlsWidth;

  @override
  double get windowDragHandleWidth => overrides['windowDragHandleWidth'] ?? base.windowDragHandleWidth;

  @override
  double get windowTitleBarContentNudge => overrides['windowTitleBarContentNudge'] ?? base.windowTitleBarContentNudge;

  @override
  double get windowTopPadding => overrides['windowTopPadding'] ?? base.windowTopPadding;

  @override
  double get windowSidePadding => overrides['windowSidePadding'] ?? base.windowSidePadding;

  @override
  double get areaGap => overrides['areaGap'] ?? base.areaGap;

  @override
  double get windowBottomPadding => overrides['windowBottomPadding'] ?? base.windowBottomPadding;

  @override
  double get pathHeaderHeight => overrides['pathHeaderHeight'] ?? base.pathHeaderHeight;

  @override
  double get pathHeaderRadius => overrides['pathHeaderRadius'] ?? base.pathHeaderRadius;

  @override
  double get pathHeaderMinInset => overrides['pathHeaderMinInset'] ?? base.pathHeaderMinInset;

  @override
  double get panelRadius => overrides['panelRadius'] ?? base.panelRadius;

  @override
  double get panelTopPadding => overrides['panelTopPadding'] ?? base.panelTopPadding;

  @override
  double get headerRowHeight => overrides['headerRowHeight'] ?? base.headerRowHeight;

  @override
  double get rowHeight => overrides['rowHeight'] ?? base.rowHeight;

  @override
  double get rowGap => overrides['rowGap'] ?? base.rowGap;

  @override
  double get statusBarHeight => overrides['statusBarHeight'] ?? base.statusBarHeight;

  @override
  double get panelLeftPadding => overrides['panelLeftPadding'] ?? base.panelLeftPadding;

  @override
  double get panelRightPadding => overrides['panelRightPadding'] ?? base.panelRightPadding;

  @override
  double get labelPadding => overrides['labelPadding'] ?? base.labelPadding;

  @override
  double get columnGap => overrides['columnGap'] ?? base.columnGap;

  @override
  double get markedBarWidth => overrides['markedBarWidth'] ?? base.markedBarWidth;

  @override
  double get tileGap => overrides['tileGap'] ?? base.tileGap;

  @override
  double get nameBottomPadding => overrides['nameBottomPadding'] ?? base.nameBottomPadding;

  @override
  double get iconLeftPadding => overrides['iconLeftPadding'] ?? base.iconLeftPadding;

  @override
  double get iconGap => overrides['iconGap'] ?? base.iconGap;

  @override
  double get iconColumnWidth => overrides['iconColumnWidth'] ?? base.iconColumnWidth;

  @override
  double get treeMarkGap => overrides['treeMarkGap'] ?? base.treeMarkGap;

  @override
  double get functionButtonHeight => overrides['functionButtonHeight'] ?? base.functionButtonHeight;

  @override
  double get functionButtonRadius => overrides['functionButtonRadius'] ?? base.functionButtonRadius;

  @override
  double get functionKeyNumberWidth => overrides['functionKeyNumberWidth'] ?? base.functionKeyNumberWidth;

  @override
  double get functionKeyNumberGap => overrides['functionKeyNumberGap'] ?? base.functionKeyNumberGap;

  @override
  double get functionButtonGap => overrides['functionButtonGap'] ?? base.functionButtonGap;

  @override
  double get functionBarSideOutset => overrides['functionBarSideOutset'] ?? base.functionBarSideOutset;

  @override
  double get functionBarRightPadding => overrides['functionBarRightPadding'] ?? base.functionBarRightPadding;

  @override
  double get dialogRadius => overrides['dialogRadius'] ?? base.dialogRadius;

  @override
  double get dialogWidthFactor => overrides['dialogWidthFactor'] ?? base.dialogWidthFactor;

  @override
  double get paletteWidthFactor => overrides['paletteWidthFactor'] ?? base.paletteWidthFactor;

  @override
  double get dialogMinWidth => overrides['dialogMinWidth'] ?? base.dialogMinWidth;

  @override
  double get dialogMaxWidth => overrides['dialogMaxWidth'] ?? base.dialogMaxWidth;

  @override
  double get dialogMinHeight => overrides['dialogMinHeight'] ?? base.dialogMinHeight;

  @override
  double get dialogResizeEdge => overrides['dialogResizeEdge'] ?? base.dialogResizeEdge;

  @override
  double get dialogTitleHeight => overrides['dialogTitleHeight'] ?? base.dialogTitleHeight;

  @override
  double get dialogPadding => overrides['dialogPadding'] ?? base.dialogPadding;

  @override
  double get dialogHorizontalPadding => overrides['dialogHorizontalPadding'] ?? base.dialogHorizontalPadding;

  @override
  double get dialogContentTopPadding => overrides['dialogContentTopPadding'] ?? base.dialogContentTopPadding;

  @override
  double get dialogGap => overrides['dialogGap'] ?? base.dialogGap;

  @override
  double get dialogLineGap => overrides['dialogLineGap'] ?? base.dialogLineGap;

  @override
  double get dialogWideRowGap => overrides['dialogWideRowGap'] ?? base.dialogWideRowGap;

  @override
  double get dialogSectionGap => overrides['dialogSectionGap'] ?? base.dialogSectionGap;

  @override
  double get settingsWidthFactor => overrides['settingsWidthFactor'] ?? base.settingsWidthFactor;

  @override
  double get sectionHeadingFontSize => overrides['sectionHeadingFontSize'] ?? base.sectionHeadingFontSize;

  @override
  double get settingsTocWidth => overrides['settingsTocWidth'] ?? base.settingsTocWidth;

  @override
  double get sectionEntryGap => overrides['sectionEntryGap'] ?? base.sectionEntryGap;

  @override
  double get sectionGap => overrides['sectionGap'] ?? base.sectionGap;

  @override
  double get dialogLabelWidth => overrides['dialogLabelWidth'] ?? base.dialogLabelWidth;

  @override
  double get dialogLabelMaxWidth => overrides['dialogLabelMaxWidth'] ?? base.dialogLabelMaxWidth;

  @override
  double get helpCellMaxWidth => overrides['helpCellMaxWidth'] ?? base.helpCellMaxWidth;

  @override
  double get dialogTopInset => overrides['dialogTopInset'] ?? base.dialogTopInset;

  @override
  double get dialogScreenInset => overrides['dialogScreenInset'] ?? base.dialogScreenInset;

  @override
  double get dialogAreaInset => overrides['dialogAreaInset'] ?? base.dialogAreaInset;

  @override
  double get dialogMaxScreenFactor => overrides['dialogMaxScreenFactor'] ?? base.dialogMaxScreenFactor;

  @override
  double get dialogDragKeepVisible => overrides['dialogDragKeepVisible'] ?? base.dialogDragKeepVisible;

  @override
  double get dialogShadowOffset => overrides['dialogShadowOffset'] ?? base.dialogShadowOffset;

  @override
  double get dialogShadowBlur => overrides['dialogShadowBlur'] ?? base.dialogShadowBlur;

  @override
  double get toastPadding => overrides['toastPadding'] ?? base.toastPadding;

  @override
  double get toastHorizontalPadding => overrides['toastHorizontalPadding'] ?? base.toastHorizontalPadding;

  @override
  double get toastBottomOffset => overrides['toastBottomOffset'] ?? base.toastBottomOffset;

  @override
  double get buttonHeight => overrides['buttonHeight'] ?? base.buttonHeight;

  @override
  double get buttonRadius => overrides['buttonRadius'] ?? base.buttonRadius;

  @override
  double get buttonHorizontalPadding => overrides['buttonHorizontalPadding'] ?? base.buttonHorizontalPadding;

  @override
  double get buttonShadowOffset => overrides['buttonShadowOffset'] ?? base.buttonShadowOffset;

  @override
  double get buttonShadowBlur => overrides['buttonShadowBlur'] ?? base.buttonShadowBlur;

  @override
  double get checkboxSize => overrides['checkboxSize'] ?? base.checkboxSize;

  @override
  double get checkboxGap => overrides['checkboxGap'] ?? base.checkboxGap;

  @override
  double get inputHeight => overrides['inputHeight'] ?? base.inputHeight;

  @override
  double get inputRadius => overrides['inputRadius'] ?? base.inputRadius;

  @override
  double get inputHorizontalPadding => overrides['inputHorizontalPadding'] ?? base.inputHorizontalPadding;

  @override
  double get commandLineHeight => overrides['commandLineHeight'] ?? base.commandLineHeight;

  @override
  double get progressHeight => overrides['progressHeight'] ?? base.progressHeight;

  @override
  double get progressInset => overrides['progressInset'] ?? base.progressInset;

  @override
  double get scrollbarInset => overrides['scrollbarInset'] ?? base.scrollbarInset;

  @override
  double get strokeWidth => overrides['strokeWidth'] ?? base.strokeWidth;

  @override
  double get focusRingWidth => overrides['focusRingWidth'] ?? base.focusRingWidth;

  @override
  double get caretWidth => overrides['caretWidth'] ?? base.caretWidth;

  @override
  double get caretRadius => overrides['caretRadius'] ?? base.caretRadius;

  @override
  double get fontSize => overrides['fontSize'] ?? base.fontSize;

  @override
  double get iconSize => overrides['iconSize'] ?? base.iconSize;

  @override
  double get cellPadding => overrides['cellPadding'] ?? base.cellPadding;

  @override
  double get rowContentVerticalNudge => overrides['rowContentVerticalNudge'] ?? base.rowContentVerticalNudge;

  @override
  double get rowTextVerticalNudge => overrides['rowTextVerticalNudge'] ?? base.rowTextVerticalNudge;

  @override
  double get resizeHandleWidth => overrides['resizeHandleWidth'] ?? base.resizeHandleWidth;

  @override
  double get minPanelWidth => overrides['minPanelWidth'] ?? base.minPanelWidth;
}
