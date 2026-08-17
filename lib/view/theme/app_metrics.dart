/// Размеры интерфейса — по референсному приложению.
///
/// Все значения выведены из исходных чисел MXML через единый коэффициент
/// [scale], поэтому пропорции референса сохранены точно, а общий размер
/// интерфейса меняется одной строкой. Рядом с каждым значением указан его
/// исходник, чтобы сверка с референсом была построчной.
class FcMetrics {
  const FcMetrics();

  /// Во сколько раз интерфейс мельче исходных чисел референса.
  ///
  /// Референс нарисован в координатах `applicationDPI="320"`, и простое деление
  /// пополам даёт заметно более крупный интерфейс, чем он выглядел на экране.
  /// Коэффициент подобран по живому приложению: шаг строк выходит 20 точек,
  /// кегль — 13.6.
  static const double scale = 0.4;

  double _ref(double value) => value * scale;

  // --- окно (Main.mxml) ---

  /// Отступ от верха окна до панелей: `top="20"`.
  double get windowTopPadding => _ref(20);

  /// Зазор между панелями: `width / 2 - 10` у обеих.
  double get panelGap => _ref(20);

  /// Просвет между панелями и нижней панелью кнопок.
  double get functionBarGap => _ref(15);

  /// Отступ от низа окна: `bottom="15"` у списка кнопок.
  double get windowBottomPadding => _ref(15);

  // --- панель (FilesPanel.mxml) ---

  /// Плашка с путём: `height="60"`, скругление `radiusX="5"`.
  /// Она наполовину заходит на верхнюю рамку панели — рамка начинается с
  /// `top="30"`, то есть ровно с середины плашки.
  double get pathHeaderHeight => _ref(60);
  double get pathHeaderRadius => _ref(5);

  /// Насколько плашка уже панели: `maxWidth="{width - 100}"`.
  double get pathHeaderMinInset => _ref(50);

  /// Отступ от рамки панели до строки заголовков: `top="80"` при рамке с 30.
  double get panelTopPadding => _ref(50);

  /// От заголовков до первой строки: список начинается с `top="135"`.
  double get headerRowHeight => _ref(55);

  /// Строка списка: `height="50"` у `FileItemRenderer`, `gap="2"` в раскладке.
  double get rowHeight => _ref(50);
  double get rowGap => _ref(2);

  /// Строка состояния: линейка над ней стоит на `bottom="60"`.
  double get statusBarHeight => _ref(60);

  /// Поля внутри панели: заголовки `left="30"`, содержимое строки `right="40"`.
  double get panelLeftPadding => _ref(30);
  double get panelRightPadding => _ref(40);

  /// Поля строки состояния и плашки пути: `left="20"` у обеих меток.
  double get labelPadding => _ref(20);

  /// Зазор между колонками: `gap="30"` у заголовков, `gap="20"` у строки.
  double get columnGap => _ref(20);

  /// Полоса, отмечающая помеченный объект у левого края строки: `width="8"`.
  double get markedBarWidth => _ref(8);

  /// Отступ от края строки до иконки: `left="30"`.
  double get iconLeftPadding => _ref(30);

  /// Просвет от иконки до имени.
  ///
  /// Имя стоит на `left="{iconLabel.width + 50}"`, сама иконка — на `left="30"`,
  /// то есть между ними 20 единиц. Плюс пробел, зашитый в каждый глиф
  /// (`"\uf07b "` в `icon.as`): он входит в `iconLabel.width`.
  ///
  /// По этой арифметике выходит 28, но на глаз просвет великоват: `Icon` во
  /// Flutter отводит глифу квадрат по кеглю, а папка уже своего квадрата, и
  /// этот запас добавляется к просвету сам. Отсюда 19.
  double get iconGap => _ref(19);

  /// Ширина колонки с иконкой: отступ слева, глиф и просвет до имени.
  ///
  /// Поле ячейки имени ([cellPadding]) — часть того же просвета, поэтому оно
  /// вычитается: иначе имя отойдёт от иконки дальше, чем в референсе.
  double get iconColumnWidth => iconLeftPadding + iconSize + iconGap - cellPadding;

  // --- нижняя панель (FunctionKeyRenderer) ---

  /// Высота кнопки: `rowHeight="55"`.
  double get functionButtonHeight => _ref(55);

  /// Скругление кнопки: `radiusX="5"`.
  double get functionButtonRadius => _ref(5);

  /// Ширина колонки с номером клавиши: `width="50"` у метки номера.
  ///
  /// Шире исходного: в референсе там стояла одна цифра, а у нас — `F1`…`F10`.
  double get functionKeyNumberWidth => _ref(75);

  /// Просвет между кнопкой и её номером: кнопка начинается с `left="55"`.
  double get functionKeyNumberGap => _ref(5);

  /// Зазор между кнопками: `horizontalGap="20"`.
  double get functionButtonGap => _ref(20);

  /// Поле справа у ряда кнопок: `paddingRight="30"`.
  double get functionBarRightPadding => _ref(30);

  // --- окна команд (TitledPopupPanelSkin) ---

  /// Скругление окна: `radiusX="10"`.
  double get dialogRadius => _ref(10);

  /// Ширина окна команды: `minWidth="1000" maxWidth="2000"`.
  ///
  /// Окно раздаётся по содержимому в этих пределах — прежде всего по ряду
  /// кнопок, ширина которых зависит от подписей.
  double get dialogMinWidth => _ref(1000);
  double get dialogMaxWidth => _ref(2000);

  /// Полоса заголовка: `left="20"` у метки.
  double get dialogTitlePadding => _ref(20);

  /// Высота полосы заголовка: `top="25"` + кегль `h5` (34) + `bottom="25"`.
  ///
  /// Задана высотой, а не полями: иначе к 25 сверху и снизу прибавился бы ещё
  /// межстрочный просвет, который Flutter кладёт внутрь строки, и полоса вышла
  /// бы выше референсной.
  double get dialogTitleHeight => _ref(84);

  /// Содержимое: `padding="20" paddingLeft="40"`.
  double get dialogPadding => _ref(20);
  double get dialogHorizontalPadding => _ref(40);

  /// Отступ от полосы заголовка до первой строки содержимого.
  ///
  /// Больше обычного [dialogPadding]: к нему в референсе добавляется смещение
  /// первой строки формы — `baseline="maxAscent:10"` в `SimpleFormItemSkin`.
  double get dialogContentTopPadding => _ref(30);

  /// Между строками содержимого и между кнопками: `gap="20"`.
  double get dialogGap => _ref(20);

  /// Линия над рядом кнопок: `height="2"`.
  double get dialogDividerHeight => 1;

  /// Ширина колонки подписей в форме окна.
  double get dialogLabelWidth => _ref(220);

  /// Тень окна: `DropShadowFilter distance="5" blurX="15" blurY="15"`.
  double get dialogShadowOffset => _ref(5);
  double get dialogShadowBlur => _ref(15);

  // --- кнопка окна команды (RegularButtonSkin) ---

  /// `height="60"`, `radiusX="8"`, метка с полями `left="40"`.
  double get buttonHeight => _ref(60);
  double get buttonRadius => _ref(8);
  double get buttonHorizontalPadding => _ref(40);

  /// Тень под кнопкой и под полосой заголовка окна:
  /// `DropShadowFilter blurY="2" blurX="0" distance="1" angle="90"`.
  ///
  /// Как и [strokeWidth], не по [scale]: после уменьшения тень стала бы тоньше
  /// точки и исчезла бы совсем.
  double get buttonShadowOffset => 1;
  double get buttonShadowBlur => 2;

  // --- поле ввода (TextInputBorderedSkin) ---

  /// `height="70"`, `radiusX="8"`, текст с `left="22"`.
  double get inputHeight => _ref(70);
  double get inputRadius => _ref(8);
  double get inputHorizontalPadding => _ref(22);

  // --- полоса хода работы (ProgressBar.mxml) ---

  /// `height="30"`, скругление в половину высоты, заливка с отступом `4`.
  double get progressHeight => _ref(30);
  double get progressInset => _ref(4);

  // --- общее ---

  /// Толщина обводок: `weight="2"` в референсе.
  ///
  /// Единственное значение не по [scale]: после уменьшения линия стала бы тоньше
  /// точки и размылась бы, а в референсе она чёткая.
  double get strokeWidth => 1;

  /// Размер шрифта: `h5` — `fontSize: 34px`.
  double get fontSize => _ref(34);

  /// Иконка — глиф того же кегля, что и текст (`styleName="h5 ... icon"`).
  double get iconSize => _ref(34);

  /// Поле внутри ячейки таблицы: половина зазора между колонками.
  double get cellPadding => _ref(10);

  /// Насколько текст опущен относительно середины строки.
  ///
  /// В референсе иконка стоит на `verticalCenter="0"`, а группа с текстом — на
  /// `verticalCenter="2"`, и плашка пути тоже. Это не случайность: у Consolas
  /// на некоторых кеглях базовая линия смещена, и без этой поправки текст не
  /// встаёт на одну линию с иконкой.
  double get textVerticalNudge => _ref(2);

  /// Ширина области захвата разделителя панелей и границ колонок.
  /// Не уже [panelGap]: иначе разделитель было бы труднее подцепить, чем видно.
  double get resizeHandleWidth => 10;

  /// Минимальная ширина панели при перетаскивании разделителя.
  double get minPanelWidth => 220;
}
