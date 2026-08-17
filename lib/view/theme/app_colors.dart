import 'package:flutter/painting.dart';

/// Палитра референсного приложения — `resources/styles/palette.as`.
///
/// Отдельный набор именно исходных цветов: по нему видно, откуда взято каждое
/// значение, и его можно сверить с референсом строка в строку. Роли (что чем
/// красится) описаны ниже в [FcColors].
abstract final class FcPalette {
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF57585F);
  static const Color red = Color(0xFFDE1D2E);
  static const Color green = Color(0xFF3BA839);
  static const Color yellow = Color(0xFFF5BB30);

  static const Color gray2 = Color(0xFFE2E2E2);
  static const Color gray1 = Color(0xFFBBBBBB);
  static const Color gray0 = Color(0xFFD9D9D9);

  static const Color blue3 = Color(0xFF011130);
  static const Color blue2 = Color(0xFF15387E);
  static const Color blue1 = Color(0xFF3B5A96);
  static const Color blue0 = Color(0xFF9AA7C1);

  static const Color sea = Color(0xFF04345B);
  static const Color sea2 = Color(0xFF011E37);

  /// Полоса пометки в списке файлов (`FileItemRenderer`, `#289ff4`).
  static const Color marker = Color(0xFF289FF4);

  /// Подписи нижней панели (`FunctionKeyRenderer`, `#95ABBD`).
  static const Color functionKey = Color(0xFF95ABBD);

  /// Разделительная линия в окне команды (`TitledPopupPanelSkin`, `#191d25`).
  static const Color dialogDivider = Color(0xFF191D25);
}

/// Цвета интерфейса по их роли.
///
/// Виджеты не содержат цветов: всё, чем они красятся, названо здесь. Тема одна —
/// та же, что у референсного приложения; светлой темы нет, поэтому и выбирать
/// не из чего.
///
/// Прозрачность в референсе задана отдельно от цвета (`alpha="0.15"` у обводок,
/// `0.05` у фона панели), здесь она вписана прямо в значение.
class FcColors {
  const FcColors();

  /// Фон окна.
  Color get windowBackground => FcPalette.blue3;

  // --- панель ---

  /// Панель поверх фона окна: белый с прозрачностью 5%.
  Color get panelBackground => FcPalette.white.withValues(alpha: 0.05);

  /// Обводка панели и линейки внутри неё: белый 15%.
  Color get panelBorder => FcPalette.white.withValues(alpha: 0.15);

  /// Вертикальные линейки между колонками и линия над строкой состояния.
  Color get columnDivider => panelBorder;

  // --- список файлов ---

  Color get rowText => FcPalette.blue0;

  /// Каталоги и файлы в референсе одного цвета: тип виден по иконке.
  Color get directoryText => FcPalette.blue0;

  Color get sizeText => FcPalette.blue0;

  Color get secondaryText => FcPalette.blue0;

  Color get headerText => FcPalette.white;

  /// Курсор рисуется только в активной панели.
  Color get cursorBackground => FcPalette.blue2;

  Color get cursorText => FcPalette.white;

  /// Помеченная строка: подсветка фона (белый 8%) и полоса у левого края.
  Color get markedBackground => FcPalette.white.withValues(alpha: 0.08);

  Color get markedBar => FcPalette.marker;

  /// Иконка типа объекта приглушена (`alpha="0.6"` у `iconLabel`).
  Color get icon => FcPalette.blue0.withValues(alpha: 0.6);

  Color get iconSelected => FcPalette.white;

  // --- плашка пути ---

  Color get pathBackground => FcPalette.sea;

  Color get pathBorder => panelBorder;

  Color get pathText => FcPalette.white;

  /// Пассивная панель в референсе плашкой не отличалась, но панелей две и
  /// понимать, какая из них принимает клавиши, нужно: у пассивной плашка
  /// приглушена.
  Color get pathInactiveBackground => FcPalette.sea2;

  Color get pathInactiveText => FcPalette.blue0;

  // --- нижняя панель ---

  Color get functionButtonBackground => FcPalette.sea;

  Color get functionButtonText => FcPalette.functionKey;

  Color get functionKeyNumber => FcPalette.functionKey;

  // --- окна команд ---

  Color get dialogBackground => FcPalette.sea2;

  Color get dialogTitleBackground => FcPalette.sea;

  Color get dialogTitleText => FcPalette.white;

  Color get dialogDivider => FcPalette.dialogDivider;

  Color get dialogLabel => FcPalette.white;

  Color get dialogText => FcPalette.blue0;

  /// Затемнение под окном команды.
  Color get dialogBarrier => FcPalette.blue3.withValues(alpha: 0.6);

  // --- кнопки окна команды ---

  Color get buttonBackground => FcPalette.sea;

  /// Кнопка подтверждения (`s|Button.default`).
  Color get buttonPrimaryBackground => FcPalette.blue1;

  Color get buttonText => FcPalette.white;

  /// Тонкая обводка кнопок: чёрный 4%.
  Color get buttonBorder => const Color(0xFF000000).withValues(alpha: 0.04);

  /// Затемнение нажатой кнопки: чёрный 20%.
  Color get buttonPressed => const Color(0xFF000000).withValues(alpha: 0.2);

  // --- поле ввода ---

  Color get inputBackground => FcPalette.white.withValues(alpha: 0.07);

  Color get inputBorder => FcPalette.white.withValues(alpha: 0.11);

  Color get inputText => FcPalette.white;

  Color get inputHint => FcPalette.white.withValues(alpha: 0.6);

  /// Выделение текста в поле ввода (`focusedTextSelectionColor`).
  Color get inputSelection => FcPalette.red;

  // --- прочее ---

  /// Полоса хода работы: обводка и заливка одного цвета.
  Color get progress => FcPalette.blue0;

  Color get error => FcPalette.red;
}
