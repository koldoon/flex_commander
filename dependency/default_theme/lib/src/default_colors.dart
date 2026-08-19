import 'package:fc_api/fc_api.dart';
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

/// Цвета оформления по умолчанию: роли из [FcColors], значения из [FcPalette].
///
/// Тема со своей палитрой наследуется отсюда и переопределяет то, что ей
/// нужно, — остальное останется прежним.
class DefaultColors extends FcColors {
  const DefaultColors();

  @override
  Color get windowBackground => FcPalette.blue3;

  // --- панель ---

  @override
  Color get panelBackground => FcPalette.white.withValues(alpha: 0.05);

  @override
  Color get panelBorder => FcPalette.white.withValues(alpha: 0.15);

  @override
  Color get columnDivider => panelBorder;

  // --- список файлов ---

  @override
  Color get rowText => FcPalette.blue0;

  @override
  Color get directoryText => FcPalette.blue0;

  @override
  Color get sizeText => FcPalette.blue0;

  @override
  Color get secondaryText => FcPalette.blue0;

  @override
  Color get headerText => FcPalette.white;

  @override
  Color get cursorBackground => FcPalette.blue2;

  @override
  Color get cursorText => FcPalette.white;

  @override
  Color get markedBackground => FcPalette.white.withValues(alpha: 0.08);

  @override
  Color get markedBar => FcPalette.marker;

  @override
  Color get icon => FcPalette.blue0.withValues(alpha: 0.6);

  @override
  Color get iconSelected => FcPalette.white;

  // --- плашка пути ---

  @override
  Color get pathBackground => FcPalette.sea;

  @override
  Color get pathBorder => panelBorder;

  @override
  Color get pathText => FcPalette.white;

  @override
  Color get pathInactiveBackground => FcPalette.sea2;

  @override
  Color get pathInactiveText => FcPalette.blue0;

  // --- нижняя панель ---

  @override
  Color get functionButtonBackground => FcPalette.sea;

  @override
  Color get functionButtonText => FcPalette.functionKey;

  @override
  Color get functionKeyNumber => FcPalette.functionKey;

  // --- окна команд ---

  @override
  Color get dialogBackground => FcPalette.sea2;

  @override
  Color get dialogTitleBackground => FcPalette.sea;

  @override
  Color get dialogTitleText => FcPalette.white;

  @override
  Color get dialogDivider => FcPalette.dialogDivider;

  @override
  Color get dialogLabel => FcPalette.white;

  @override
  Color get dialogText => FcPalette.blue0;

  @override
  Color get dialogBarrier => FcPalette.blue3.withValues(alpha: 0.6);

  // --- кнопки окна команды ---

  @override
  Color get buttonBackground => FcPalette.sea;

  @override
  Color get buttonPrimaryBackground => FcPalette.blue1;

  @override
  Color get buttonText => FcPalette.white;

  @override
  Color get buttonBorder => const Color(0xFF000000).withValues(alpha: 0.04);

  @override
  Color get buttonPressed => const Color(0xFF000000).withValues(alpha: 0.2);

  // --- поле ввода ---

  @override
  Color get inputBackground => FcPalette.white.withValues(alpha: 0.07);

  @override
  Color get inputBorder => FcPalette.white.withValues(alpha: 0.11);

  @override
  Color get inputText => FcPalette.white;

  @override
  Color get inputHint => FcPalette.white.withValues(alpha: 0.6);

  @override
  Color get inputSelection => FcPalette.red;

  @override
  Color get shadow => const Color(0xFF000000).withValues(alpha: 0.25);

  // --- прочее ---

  @override
  Color get progress => FcPalette.blue0;

  @override
  Color get error => FcPalette.red;
}
