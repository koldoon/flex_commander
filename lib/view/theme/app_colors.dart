import 'package:flutter/painting.dart';

/// Палитра приложения.
///
/// Значения светлой темы сняты с макета `docs/design/design.svg`, тёмной —
/// с референсного приложения на Adobe Flex. Виджеты не содержат цветов:
/// вторая тема не должна требовать правок по всему дереву.
class FcColors {
  const FcColors({
    required this.windowBackgroundTop,
    required this.windowBackgroundBottom,
    required this.panelBackground,
    required this.panelBorder,
    required this.columnDivider,
    required this.rowText,
    required this.directoryText,
    required this.sizeText,
    required this.secondaryText,
    required this.headerText,
    required this.cursorBackground,
    required this.cursorBorder,
    required this.cursorText,
    required this.markedBackground,
    required this.markedBar,
    required this.pathActiveBackground,
    required this.pathActiveBorder,
    required this.pathInactiveBackground,
    required this.pathInactiveBorder,
    required this.pathText,
    required this.buttonTop,
    required this.buttonBottom,
    required this.buttonBorder,
    required this.buttonText,
    required this.folderIcon,
    required this.error,
  });

  final Color windowBackgroundTop;
  final Color windowBackgroundBottom;

  final Color panelBackground;
  final Color panelBorder;

  /// Вертикальные линейки между колонками и линия над строкой состояния.
  final Color columnDivider;

  final Color rowText;
  final Color directoryText;
  final Color sizeText;
  final Color secondaryText;
  final Color headerText;

  /// Курсор рисуется только в активной панели.
  final Color cursorBackground;
  final Color cursorBorder;
  final Color cursorText;

  /// Помеченная строка: подсветка фона и полоса у левого края.
  final Color markedBackground;
  final Color markedBar;

  final Color pathActiveBackground;
  final Color pathActiveBorder;
  final Color pathInactiveBackground;
  final Color pathInactiveBorder;
  final Color pathText;

  final Color buttonTop;
  final Color buttonBottom;
  final Color buttonBorder;
  final Color buttonText;

  final Color folderIcon;
  final Color error;

  static const FcColors light = FcColors(
    windowBackgroundTop: Color(0xFFFAFAFA),
    windowBackgroundBottom: Color(0xFFD9D9D9),
    panelBackground: Color(0xFFFFFFFF),
    panelBorder: Color(0x3D000000),
    columnDivider: Color(0x1F000000),
    rowText: Color(0xFF444444),
    directoryText: Color(0xFF333333),
    sizeText: Color(0xFF555555),
    secondaryText: Color(0xFF737373),
    headerText: Color(0xFF333333),
    cursorBackground: Color(0xFF0169D9),
    cursorBorder: Color(0xFF0063CD),
    cursorText: Color(0xFFFFFFFF),
    markedBackground: Color(0xFFEDEDED),
    markedBar: Color(0xFF4BB9F4),
    pathActiveBackground: Color(0xFF0169D9),
    pathActiveBorder: Color(0xFF0063CD),
    pathInactiveBackground: Color(0xFFB0B1AF),
    pathInactiveBorder: Color(0xFFA0A0A0),
    pathText: Color(0xFFFFFFFF),
    buttonTop: Color(0xFFFDFDFD),
    buttonBottom: Color(0xFFF1F1F1),
    buttonBorder: Color(0x44000000),
    buttonText: Color(0xFF444444),
    folderIcon: Color(0xFF4BB9F4),
    error: Color(0xFFDE1D2E),
  );

  /// Палитра референсного приложения: тёмно-синее окно, полупрозрачные панели.
  static const FcColors dark = FcColors(
    windowBackgroundTop: Color(0xFF011130),
    windowBackgroundBottom: Color(0xFF011130),
    panelBackground: Color(0x0DFFFFFF),
    panelBorder: Color(0x26FFFFFF),
    columnDivider: Color(0x1AFFFFFF),
    rowText: Color(0xFF9AA7C1),
    directoryText: Color(0xFFD9D9D9),
    sizeText: Color(0xFF9AA7C1),
    secondaryText: Color(0xFF95ABBD),
    headerText: Color(0xFFFFFFFF),
    cursorBackground: Color(0xFF15387E),
    cursorBorder: Color(0xFF3B5A96),
    cursorText: Color(0xFFFFFFFF),
    markedBackground: Color(0x14FFFFFF),
    markedBar: Color(0xFF289FF4),
    pathActiveBackground: Color(0xFF04345B),
    pathActiveBorder: Color(0x26FFFFFF),
    pathInactiveBackground: Color(0xFF1B2A44),
    pathInactiveBorder: Color(0x26FFFFFF),
    pathText: Color(0xFFFFFFFF),
    buttonTop: Color(0xFF15387E),
    buttonBottom: Color(0xFF15387E),
    buttonBorder: Color(0x26FFFFFF),
    buttonText: Color(0xFF95ABBD),
    folderIcon: Color(0xFF4BB9F4),
    error: Color(0xFFDE1D2E),
  );
}
