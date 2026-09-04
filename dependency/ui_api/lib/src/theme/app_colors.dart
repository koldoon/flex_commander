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

  Color get dialogLabel;

  Color get dialogText;

  /// Затемнение под окном команды.
  Color get dialogBarrier;

  /// Область списка внутри окна команды: находки поиска.
  ///
  /// **Не панельные роли, хотя список тот же.** Панель стоит на фоне окна
  /// приложения, а список — в окне команды, у которого фон свой и посветлее;
  /// цвет, подобранный под первый, ко второму не идёт. И не поле ввода: в нём
  /// набирают, а здесь ходят курсором по файлам.
  ///
  /// С умолчанием, а не обязательные: тема, написанная до появления окна
  /// находок, обязана продолжать работать, и поле ввода — разумное «то же
  /// самое».
  Color get dialogListBackground => inputBackground;

  Color get dialogListBorder => inputBorder;

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

  /// Обводка того, что сейчас в фокусе: поля, флажка, кнопки.
  ///
  /// Обводка, а не подсветка фона: фон уже занят — у поля свой, у кнопки заливка
  /// скина, у нажатой затемнение. Обводка ложится поверх любого из них и ничего
  /// не перекрашивает.
  ///
  /// С умолчанием, а не обязательная: тема, написанная до появления фокуса,
  /// обязана продолжать работать, и рамка поля — разумное «то же самое».
  Color get focusRing => inputBorder;

  /// Тень под кнопкой, полосой заголовка и самим окном: чёрный 25 %
  /// (`DropShadowFilter alpha="0.25"`).
  Color get shadow;

  // --- подсветка синтаксиса ---
  //
  // Роли, а не готовая тема подсветки: цвет решает оформление приложения, а не
  // библиотека, которой его разбирают. Ролей нарочно немного — просмотрщик не
  // редактор, и различать сорок видов токенов в нём незачем; всё, что не
  // названо здесь, рисуется обычным цветом строки.

  /// Ключевые слова языка: `if`, `class`, `return`.
  Color get syntaxKeyword;

  /// Строковые литералы вместе с кавычками.
  Color get syntaxString;

  /// Числа.
  Color get syntaxNumber;

  /// Комментарии.
  Color get syntaxComment;

  /// Имена типов, классов и функций в объявлениях.
  Color get syntaxType;

  /// Готовые значения языка: `true`, `null`, встроенные имена.
  Color get syntaxLiteral;

  /// То, что стоит вокруг кода: аннотации, директивы, заголовки разделов.
  Color get syntaxMeta;

  // --- прочее ---

  /// Полоса хода работы: обводка и заливка одного цвета.
  Color get progress;

  Color get error;
}
