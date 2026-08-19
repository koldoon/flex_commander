import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Размеры оформления по умолчанию — по референсному приложению.
///
/// Все значения выведены из исходных чисел MXML через единый коэффициент
/// [scale], поэтому пропорции референса сохранены точно, а общий размер
/// интерфейса меняется одной строкой. Рядом с каждым значением указан его
/// исходник, чтобы сверка с референсом была построчной.
class DefaultMetrics extends FcMetrics {
  const DefaultMetrics({this.scale = defaultScale, this.fontScale = defaultFontScale});

  /// Во сколько раз интерфейс мельче исходных чисел референса.
  ///
  /// Референс нарисован в координатах `applicationDPI="320"`, и простое деление
  /// пополам даёт заметно более крупный интерфейс, чем он выглядел на экране.
  /// Коэффициент подобран по живому приложению: шаг строк выходит 20 точек,
  /// кегль — 13.6.
  static const double defaultScale = 0.4;

  /// Отдельный коэффициент для кегля.
  ///
  /// По разметке кегль должен был бы получаться из [scale], но на снимке
  /// работающего референса видно, что текст там мельче: при шаге строк
  /// 19.4 точки кегль ≈ 12.7, тогда как отношение из CSS (34 к 50) дало бы
  /// 13.2. Замер сделан по ширине символа Consolas — шрифт моноширинный, и
  /// его шаг связан с кеглем жёстко (0.55 em), поэтому это надёжнее, чем
  /// мерить высоту букв со сглаживанием.
  static const double defaultFontScale = 0.385;

  @override
  final double scale;

  @override
  final double fontScale;

  /// Число референса в точках экрана. Наследнику оно нужно так же, как и
  /// самому набору: тема со своими размерами переопределяет отдельные
  /// значения, а не переписывает все пятьдесят.
  @protected
  double ref(double value) => value * scale;

  // --- окно (Main.mxml) ---

  @override
  double get windowTopPadding => ref(20);

  @override
  double get panelGap => ref(20);

  @override
  double get functionBarGap => ref(15);

  @override
  double get windowBottomPadding => ref(15);

  // --- панель (FilesPanel.mxml) ---

  @override
  double get pathHeaderHeight => ref(60);

  @override
  double get pathHeaderRadius => ref(5);

  @override
  double get pathHeaderMinInset => ref(50);

  @override
  double get panelTopPadding => ref(50);

  @override
  double get headerRowHeight => ref(55);

  @override
  double get rowHeight => ref(50);

  @override
  double get rowGap => ref(2);

  @override
  double get statusBarHeight => ref(60);

  @override
  double get panelLeftPadding => ref(30);

  @override
  double get panelRightPadding => ref(40);

  @override
  double get labelPadding => ref(20);

  @override
  double get columnGap => ref(20);

  @override
  double get markedBarWidth => ref(8);

  @override
  double get iconLeftPadding => ref(30);

  @override
  double get iconGap => ref(19);

  @override
  double get iconColumnWidth => iconLeftPadding + iconSize + iconGap - cellPadding;

  // --- нижняя панель (FunctionKeyRenderer) ---

  @override
  double get functionButtonHeight => ref(55);

  @override
  double get functionButtonRadius => ref(5);

  @override
  double get functionKeyNumberWidth => ref(75);

  @override
  double get functionKeyNumberGap => ref(5);

  @override
  double get functionButtonGap => ref(20);

  @override
  double get functionBarRightPadding => ref(30);

  // --- окна команд (TitledPopupPanelSkin) ---

  @override
  double get dialogRadius => ref(10);

  @override
  double get dialogWidthFactor => 0.5;

  @override
  double get dialogMinWidth => ref(1000);

  @override
  double get dialogMaxWidth => ref(2000);

  @override
  double get dialogTitlePadding => ref(20);

  @override
  double get dialogTitleHeight => ref(84);

  @override
  double get dialogPadding => ref(20);

  @override
  double get dialogHorizontalPadding => ref(40);

  @override
  double get dialogContentTopPadding => ref(30);

  @override
  double get dialogGap => ref(20);

  @override
  double get dialogDividerHeight => 1;

  @override
  double get dialogLabelWidth => ref(250);

  @override
  double get toastPadding => ref(14);

  @override
  double get toastHorizontalPadding => ref(24);

  /// Над рядом кнопок: его высота плюс поля окна снизу и небольшой просвет.
  @override
  double get toastBottomOffset => functionButtonHeight + windowBottomPadding + ref(20);

  @override
  double get helpCellMaxWidth => ref(900);

  @override
  double get dialogScreenInset => 120;

  @override
  double get dialogShadowOffset => ref(5);

  @override
  double get dialogShadowBlur => ref(15);

  // --- кнопка окна команды (RegularButtonSkin) ---

  @override
  double get buttonHeight => ref(60);

  @override
  double get buttonRadius => ref(8);

  @override
  double get buttonHorizontalPadding => ref(40);

  @override
  double get buttonShadowOffset => 1;

  @override
  double get buttonShadowBlur => 2;

  // --- поле ввода (TextInputBorderedSkin) ---

  @override
  double get checkboxSize => ref(40);

  @override
  double get checkboxGap => ref(16);

  @override
  double get inputHeight => ref(70);

  @override
  double get inputRadius => ref(8);

  @override
  double get inputHorizontalPadding => ref(22);

  // --- полоса хода работы (ProgressBar.mxml) ---

  @override
  double get progressHeight => ref(30);

  @override
  double get progressInset => ref(4);

  // --- общее ---

  @override
  double get strokeWidth => 1;

  @override
  double get fontSize => 34 * fontScale;

  @override
  double get iconSize => fontSize;

  @override
  double get cellPadding => ref(10);

  // Не через `ref`: поправка оптическая, ей незачем меняться вместе
  // с масштабом интерфейса. Полточки — на экране с удвоенной плотностью это
  // ровно один аппаратный пиксель, целая точка сдвигает уже заметно.
  @override
  double get rowContentVerticalNudge => 0.5;

  @override
  double get rowTextVerticalNudge => ref(2);

  @override
  double get resizeHandleWidth => 10;

  @override
  double get minPanelWidth => 220;
}
