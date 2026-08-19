import 'package:flutter/painting.dart';

/// Цвета приложения по ролям, а не по названиям.
///
/// Здесь только роли: что именно красится этим цветом. Сами значения приносит
/// тема — API не решает, как приложению выглядеть, он лишь называет места,
/// которые нужно покрасить. Оформление по умолчанию живёт в модуле
/// `fc_default_theme`, и любая другая тема наследуется от него, переопределяя
/// нужное.
abstract class FcColors {
  const FcColors();

  /// Фон окна.
  Color get windowBackground;

  // --- панель ---

  /// Панель поверх фона окна: белый с прозрачностью 5%.
  Color get panelBackground;

  /// Обводка панели и линейки внутри неё: белый 15%.
  Color get panelBorder;

  /// Вертикальные линейки между колонками и линия над строкой состояния.
  Color get columnDivider;

  // --- список файлов ---

  Color get rowText;

  /// Каталоги и файлы в референсе одного цвета: тип виден по иконке.
  Color get directoryText;

  Color get sizeText;

  Color get secondaryText;

  Color get headerText;

  /// Курсор рисуется только в активной панели.
  Color get cursorBackground;

  Color get cursorText;

  /// Помеченная строка: подсветка фона (белый 8%) и полоса у левого края.
  Color get markedBackground;

  Color get markedBar;

  /// Иконка типа объекта приглушена (`alpha="0.6"` у `iconLabel`).
  Color get icon;

  Color get iconSelected;

  // --- плашка пути ---

  Color get pathBackground;

  Color get pathBorder;

  Color get pathText;

  /// Пассивная панель в референсе плашкой не отличалась, но панелей две и
  /// понимать, какая из них принимает клавиши, нужно: у пассивной плашка
  /// приглушена.
  Color get pathInactiveBackground;

  Color get pathInactiveText;

  // --- нижняя панель ---

  Color get functionButtonBackground;

  Color get functionButtonText;

  Color get functionKeyNumber;

  // --- окна команд ---

  Color get dialogBackground;

  Color get dialogTitleBackground;

  Color get dialogTitleText;

  Color get dialogDivider;

  Color get dialogLabel;

  Color get dialogText;

  /// Затемнение под окном команды.
  Color get dialogBarrier;

  // --- кнопки окна команды ---

  Color get buttonBackground;

  /// Кнопка подтверждения (`s|Button.default`).
  Color get buttonPrimaryBackground;

  Color get buttonText;

  /// Тонкая обводка кнопок: чёрный 4%.
  Color get buttonBorder;

  /// Затемнение нажатой кнопки: чёрный 20%.
  Color get buttonPressed;

  // --- поле ввода ---

  Color get inputBackground;

  Color get inputBorder;

  Color get inputText;

  Color get inputHint;

  /// Выделение текста в поле ввода (`focusedTextSelectionColor`).
  Color get inputSelection;

  /// Тень под кнопкой, полосой заголовка и самим окном: чёрный 25 %
  /// (`DropShadowFilter alpha="0.25"`).
  Color get shadow;

  // --- прочее ---

  /// Полоса хода работы: обводка и заливка одного цвета.
  Color get progress;

  Color get error;
}
