import 'package:fc_api/fc_api.dart';

/// Размеры оформления по умолчанию — по референсному приложению.
///
/// Значения стоят **числами**, а не вычисляются из общего коэффициента. Раньше
/// они выводились из исходных чисел MXML умножением, и это выглядело точным:
/// пропорции референса сохранялись сами. Но польза оказалась мнимой — за
/// разные dpi отвечает Flutter, а не мы, — а вреда вышло два. Часть значений
/// всё равно стояла числом (полоса заголовка — ровно системные 28 точек), и
/// набор читался вперемешку. И главное: тому, кто пишет свою тему, приходилось
/// держать в голове коэффициент, чтобы понять, сколько же на экране получится
/// `ref(15)`.
///
/// Рядом с каждым значением указан его исходник в референсе — так сверка
/// остаётся построчной, а число видно глазами.
class DefaultMetrics extends FcMetrics {
  const DefaultMetrics();

  // --- окно (Main.mxml) ---

  /// Двадцать восемь точек — ровно системная полоса macOS: светофор стоит на
  /// привычном месте, и окно не выглядит съехавшим.
  @override
  double get windowTitleBarHeight => 28;

  @override
  double get windowTopPadding => 8;

  /// Полей нет: содержимое занимает окно целиком, как в референсе. Захочется
  /// рамку — крутится здесь, и разъезжаться нечему: величина одна на панели,
  /// полосу и ряд кнопок.
  @override
  double get windowSidePadding => 5;

  /// Шесть точек — то же расстояние, что стояло между панелями и над полосой
  /// поиска. Им отбиты друг от друга **все** области окна, и ставит его шелл.
  @override
  double get areaGap => 6;

  @override
  double get windowBottomPadding => 6;

  // --- панель (FilesPanel.mxml) ---

  @override
  double get pathHeaderHeight => 24;

  @override
  double get pathHeaderRadius => 5;

  @override
  double get pathHeaderMinInset => 20;

  /// Пять точек: столько же, сколько у полей окна, — рамка и её отступ читаются
  /// как одно целое.
  @override
  double get panelRadius => 5;

  @override
  double get panelTopPadding => 20;

  @override
  double get headerRowHeight => 22;

  @override
  double get rowHeight => 20;

  @override
  double get rowGap => 0.8;

  @override
  double get statusBarHeight => 28;

  @override
  double get panelLeftPadding => 12;

  @override
  double get panelRightPadding => 12;

  @override
  double get labelPadding => 8;

  /// 230 точек при обычном масштабе: столько вмещает разумно длинную подпись
  /// («Show progress inside a file from»), не отбирая места у значений.
  @override
  double get dialogLabelMaxWidth => 230;

  @override
  double get columnGap => 8;

  @override
  double get markedBarWidth => 3.2;

  @override
  double get iconLeftPadding => 12;

  @override
  double get iconGap => 7.6;

  @override
  double get iconColumnWidth => iconLeftPadding + iconSize + iconGap - cellPadding;

  // --- нижняя панель (FunctionKeyRenderer) ---

  @override
  double get functionButtonHeight => 22;

  @override
  double get functionButtonRadius => 5;

  @override
  double get functionKeyNumberWidth => 30;

  @override
  double get functionKeyNumberGap => 2;

  @override
  double get functionButtonGap => 8;

  @override
  double get functionBarRightPadding => 12;

  /// Пять точек: ровно столько, сколько отведено полям окна, — то есть ряд
  /// прижат к краям, как в референсе, где полей не было вовсе.
  @override
  double get functionBarSideOutset => 5;

  // --- окна команд (TitledPopupPanelSkin) ---

  @override
  double get dialogRadius => 5;

  @override
  double get dialogWidthFactor => 0.5;

  /// Три четверти — столько же, сколько окну команды дозволено вообще
  /// ([dialogMaxScreenFactor]): палитра берёт всю разрешённую ширину.
  ///
  /// Числа совпадают, но знак равенства между ними не ставится: предел — про
  /// все окна разом (справка с длинными описаниями иначе растянулась бы от
  /// края до края), а это — ширина одного, и двигать их порознь надо уметь.
  @override
  double get paletteWidthFactor => 0.75;

  @override
  double get dialogMinWidth => 400;

  @override
  double get dialogMaxWidth => 800;

  @override
  double get dialogTitlePadding => 8;

  @override
  double get dialogTitleHeight => 33.6;

  @override
  double get dialogDragKeepVisible => 96;

  @override
  double get dialogPadding => 8;

  @override
  double get dialogHorizontalPadding => 16;

  @override
  double get dialogContentTopPadding => 12;

  @override
  double get dialogGap => 8;

  @override
  double get dialogLineGap => 4;

  @override
  double get dialogWideRowGap => 12;

  @override
  double get settingsWidthFactor => 0.75;

  @override
  double get sectionHeadingFontSize => 17;

  @override
  double get settingsTocWidth => 180;

  @override
  double get sectionEntryGap => 14;

  @override
  double get sectionGap => 24;

  @override
  double get dialogDividerHeight => 1;

  @override
  double get dialogLabelWidth => 100;

  @override
  double get toastPadding => 5.6;

  @override
  double get toastHorizontalPadding => 9.6;

  /// Над рядом кнопок: его высота плюс поля окна снизу и небольшой просвет.
  @override
  double get toastBottomOffset => functionButtonHeight + windowBottomPadding + 8;

  @override
  double get helpCellMaxWidth => 360;

  @override
  double get dialogScreenInset => 120;

  /// Три четверти: окну есть куда вырасти, а панелям под ним остаётся видимый
  /// край — по нему и понятно, что окно временное.
  @override
  double get dialogMaxScreenFactor => 0.75;

  @override
  double get dialogShadowOffset => 2;

  @override
  double get dialogShadowBlur => 6;

  // --- кнопка окна команды (RegularButtonSkin) ---

  @override
  double get buttonHeight => 24;

  @override
  double get buttonRadius => 3.2;

  @override
  double get buttonHorizontalPadding => 16;

  @override
  double get buttonShadowOffset => 1;

  @override
  double get buttonShadowBlur => 2;

  // --- поле ввода (TextInputBorderedSkin) ---

  @override
  double get checkboxSize => 16;

  @override
  double get checkboxGap => 6.4;

  @override
  double get inputHeight => 28;

  @override
  double get inputRadius => 3.2;

  @override
  double get inputHorizontalPadding => 8.8;

  // --- полоса хода работы (ProgressBar.mxml) ---

  @override
  double get progressHeight => 12;

  @override
  double get progressInset => 1.6;

  // --- общее ---

  @override
  double get strokeWidth => 1;

  @override
  double get scrollbarInset => 2;

  @override
  double get fontSize => 13.09;

  @override
  double get iconSize => fontSize;

  @override
  double get cellPadding => 4;

  // Не через `ref`: поправка оптическая, ей незачем меняться вместе
  // с масштабом интерфейса. Полточки — на экране с удвоенной плотностью это
  // ровно один аппаратный пиксель, целая точка сдвигает уже заметно.
  @override
  double get rowContentVerticalNudge => 0.5;

  @override
  double get rowTextVerticalNudge => 0.8;

  @override
  double get resizeHandleWidth => 10;

  @override
  double get minPanelWidth => 220;
}
