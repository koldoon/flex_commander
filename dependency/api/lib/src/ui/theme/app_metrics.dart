import 'package:flutter/foundation.dart';

/// Размеры интерфейса — по референсному приложению.
///
/// Все значения выведены из исходных чисел MXML через единый коэффициент
/// [scale], поэтому пропорции референса сохранены точно, а общий размер
/// интерфейса меняется одной строкой. Рядом с каждым значением указан его
/// исходник, чтобы сверка с референсом была построчной.
class FcMetrics {
  const FcMetrics({this.scale = defaultScale, this.fontScale = defaultFontScale});

  /// Во сколько раз интерфейс мельче исходных чисел референса.
  ///
  /// Референс нарисован в координатах `applicationDPI="320"`, и простое деление
  /// пополам даёт заметно более крупный интерфейс, чем он выглядел на экране.
  /// Коэффициент подобран по живому приложению: шаг строк выходит 20 точек,
  /// кегль — 13.6.
  static const double defaultScale = 0.4;

  /// Во сколько раз этот набор метрик мельче исходных чисел референса.
  /// Одно число меняет размер всего интерфейса — отсюда и «крупная» тема.
  final double scale;

  /// Отдельный коэффициент для кегля.
  ///
  /// По разметке кегль должен был бы получаться из [scale], но на снимке
  /// работающего референса видно, что текст там мельче: при шаге строк
  /// 19.4 точки кегль ≈ 12.7, тогда как отношение из CSS (34 к 50) дало бы
  /// 13.2. Замер сделан по ширине символа Consolas — шрифт моноширинный, и
  /// его шаг связан с кеглем жёстко (0.55 em), поэтому это надёжнее, чем
  /// мерить высоту букв со сглаживанием.
  ///
  /// Единственное место, где значение снято с работающего приложения, а не
  /// с его исходников.
  static const double defaultFontScale = 0.385;

  /// Коэффициент кегля этого набора метрик.
  final double fontScale;

  /// Число референса в точках экрана. Наследнику оно нужно так же, как и
  /// самому набору: тема со своими размерами переопределяет отдельные
  /// значения, а не переписывает все пятьдесят.
  @protected
  double ref(double value) => value * scale;

  // --- окно (Main.mxml) ---

  /// Отступ от верха окна до панелей: `top="20"`.
  double get windowTopPadding => ref(20);

  /// Зазор между панелями: `width / 2 - 10` у обеих.
  double get panelGap => ref(20);

  /// Просвет между панелями и нижней панелью кнопок.
  double get functionBarGap => ref(15);

  /// Отступ от низа окна: `bottom="15"` у списка кнопок.
  double get windowBottomPadding => ref(15);

  // --- панель (FilesPanel.mxml) ---

  /// Плашка с путём: `height="60"`, скругление `radiusX="5"`.
  /// Она наполовину заходит на верхнюю рамку панели — рамка начинается с
  /// `top="30"`, то есть ровно с середины плашки.
  double get pathHeaderHeight => ref(60);
  double get pathHeaderRadius => ref(5);

  /// Насколько плашка уже панели: `maxWidth="{width - 100}"`.
  double get pathHeaderMinInset => ref(50);

  /// Отступ от рамки панели до строки заголовков: `top="80"` при рамке с 30.
  double get panelTopPadding => ref(50);

  /// От заголовков до первой строки: список начинается с `top="135"`.
  double get headerRowHeight => ref(55);

  /// Строка списка: `height="50"` у `FileItemRenderer`, `gap="2"` в раскладке.
  double get rowHeight => ref(50);
  double get rowGap => ref(2);

  /// Строка состояния: линейка над ней стоит на `bottom="60"`.
  double get statusBarHeight => ref(60);

  /// Поля внутри панели: заголовки `left="30"`, содержимое строки `right="40"`.
  double get panelLeftPadding => ref(30);
  double get panelRightPadding => ref(40);

  /// Поля строки состояния и плашки пути: `left="20"` у обеих меток.
  double get labelPadding => ref(20);

  /// Зазор между колонками: `gap="30"` у заголовков, `gap="20"` у строки.
  double get columnGap => ref(20);

  /// Полоса, отмечающая помеченный объект у левого края строки: `width="8"`.
  double get markedBarWidth => ref(8);

  /// Отступ от края строки до иконки: `left="30"`.
  double get iconLeftPadding => ref(30);

  /// Просвет от иконки до имени.
  ///
  /// Имя стоит на `left="{iconLabel.width + 50}"`, сама иконка — на `left="30"`,
  /// то есть между ними 20 единиц. Плюс пробел, зашитый в каждый глиф
  /// (`"\uf07b "` в `icon.as`): он входит в `iconLabel.width`.
  ///
  /// По этой арифметике выходит 28, но на глаз просвет великоват: `Icon` во
  /// Flutter отводит глифу квадрат по кеглю, а папка уже своего квадрата, и
  /// этот запас добавляется к просвету сам. Отсюда 19.
  double get iconGap => ref(19);

  /// Ширина колонки с иконкой: отступ слева, глиф и просвет до имени.
  ///
  /// Поле ячейки имени ([cellPadding]) — часть того же просвета, поэтому оно
  /// вычитается: иначе имя отойдёт от иконки дальше, чем в референсе.
  double get iconColumnWidth => iconLeftPadding + iconSize + iconGap - cellPadding;

  // --- нижняя панель (FunctionKeyRenderer) ---

  /// Высота кнопки: `rowHeight="55"`.
  double get functionButtonHeight => ref(55);

  /// Скругление кнопки: `radiusX="5"`.
  double get functionButtonRadius => ref(5);

  /// Ширина колонки с номером клавиши: `width="50"` у метки номера.
  ///
  /// Шире исходного: в референсе там стояла одна цифра, а у нас — `F1`…`F10`.
  double get functionKeyNumberWidth => ref(75);

  /// Просвет между кнопкой и её номером: кнопка начинается с `left="55"`.
  double get functionKeyNumberGap => ref(5);

  /// Зазор между кнопками: `horizontalGap="20"`.
  double get functionButtonGap => ref(20);

  /// Поле справа у ряда кнопок: `paddingRight="30"`.
  double get functionBarRightPadding => ref(30);

  // --- окна команд (TitledPopupPanelSkin) ---

  /// Скругление окна: `radiusX="10"`.
  double get dialogRadius => ref(10);

  /// Доля ширины окна приложения, которую занимает окно команды.
  ///
  /// Ширина именно доля, а не размер содержимого: в окне копирования по ходу
  /// работы меняются имена файлов, и от них окно «прыгало» бы на каждом файле.
  double get dialogWidthFactor => 0.5;

  /// Пределы для этой доли: `minWidth="1000" maxWidth="2000"` у диалогов
  /// референса.
  double get dialogMinWidth => ref(1000);
  double get dialogMaxWidth => ref(2000);

  /// Полоса заголовка: `left="20"` у метки.
  double get dialogTitlePadding => ref(20);

  /// Высота полосы заголовка: `top="25"` + кегль `h5` (34) + `bottom="25"`.
  ///
  /// Задана высотой, а не полями: иначе к 25 сверху и снизу прибавился бы ещё
  /// межстрочный просвет, который Flutter кладёт внутрь строки, и полоса вышла
  /// бы выше референсной.
  double get dialogTitleHeight => ref(84);

  /// Содержимое: `padding="20" paddingLeft="40"`.
  double get dialogPadding => ref(20);
  double get dialogHorizontalPadding => ref(40);

  /// Отступ от полосы заголовка до первой строки содержимого.
  ///
  /// Больше обычного [dialogPadding]: к нему в референсе добавляется смещение
  /// первой строки формы — `baseline="maxAscent:10"` в `SimpleFormItemSkin`.
  double get dialogContentTopPadding => ref(30);

  /// Между строками содержимого и между кнопками: `gap="20"`.
  double get dialogGap => ref(20);

  /// Линия над рядом кнопок: `height="2"`.
  double get dialogDividerHeight => 1;

  /// Ширина колонки подписей в форме окна.
  double get dialogLabelWidth => ref(250);

  /// Предел ширины ячейки в таблице справки: дальше строка переносится.
  ///
  /// Без него одно длинное значение — путь или описание — растянуло бы окно до
  /// полей экрана, а таблица со столбцами по содержимому под тесной разметкой
  /// не ужимается, а вылезает наружу.
  double get helpCellMaxWidth => ref(900);

  /// Поле от края окна приложения до окна справки.
  ///
  /// Единственный размер, взятый не из референса: справки там не было вовсе.
  /// Считается в точках экрана, а не в единицах разметки: это отступ от края
  /// окна, а не часть рисунка.
  double get dialogScreenInset => 120;

  /// Тень окна: `DropShadowFilter distance="5" blurX="15" blurY="15"`.
  double get dialogShadowOffset => ref(5);
  double get dialogShadowBlur => ref(15);

  // --- кнопка окна команды (RegularButtonSkin) ---

  /// `height="60"`, `radiusX="8"`, метка с полями `left="40"`.
  double get buttonHeight => ref(60);
  double get buttonRadius => ref(8);
  double get buttonHorizontalPadding => ref(40);

  /// Тень под кнопкой и под полосой заголовка окна:
  /// `DropShadowFilter blurY="2" blurX="0" distance="1" angle="90"`.
  ///
  /// Как и [strokeWidth], не по [scale]: после уменьшения тень стала бы тоньше
  /// точки и исчезла бы совсем.
  double get buttonShadowOffset => 1;
  double get buttonShadowBlur => 2;

  // --- поле ввода (TextInputBorderedSkin) ---

  /// `height="70"`, `radiusX="8"`, текст с `left="22"`.
  /// Сторона квадрата флажка и кружка переключателя: с кегль текста, чтобы
  /// метка и знак стояли на одной линии.
  double get checkboxSize => ref(40);

  /// Зазор между знаком и его меткой.
  double get checkboxGap => ref(16);

  double get inputHeight => ref(70);
  double get inputRadius => ref(8);
  double get inputHorizontalPadding => ref(22);

  // --- полоса хода работы (ProgressBar.mxml) ---

  /// `height="30"`, скругление в половину высоты, заливка с отступом `4`.
  double get progressHeight => ref(30);
  double get progressInset => ref(4);

  // --- общее ---

  /// Толщина обводок: `weight="2"` в референсе.
  ///
  /// Единственное значение не по [scale]: после уменьшения линия стала бы тоньше
  /// точки и размылась бы, а в референсе она чёткая.
  double get strokeWidth => 1;

  /// Размер шрифта: `h5` — `fontSize: 34px`, с поправкой [fontScale].
  double get fontSize => 34 * fontScale;

  /// Иконка — глиф того же кегля, что и текст (`styleName="h5 ... icon"`).
  double get iconSize => fontSize;

  /// Поле внутри ячейки таблицы: половина зазора между колонками.
  double get cellPadding => ref(10);

  /// Насколько опущен текст **строки списка** относительно её иконки.
  ///
  /// В референсе иконка стоит на `verticalCenter="0"`, а группа с текстом — на
  /// `verticalCenter="2"`. Это не случайность: у Consolas на некоторых кеглях
  /// базовая линия смещена, и без поправки текст не встаёт на одну линию
  /// с иконкой.
  ///
  /// Только к списку файлов: остальное набрано Ubuntu, и там базовая линия
  /// обычная.
  double get rowTextVerticalNudge => ref(2);

  /// Ширина области захвата разделителя панелей и границ колонок.
  /// Не уже [panelGap]: иначе разделитель было бы труднее подцепить, чем видно.
  double get resizeHandleWidth => 10;

  /// Минимальная ширина панели при перетаскивании разделителя.
  double get minPanelWidth => 220;
}
