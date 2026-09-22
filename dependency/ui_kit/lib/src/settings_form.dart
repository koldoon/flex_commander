import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'color_field.dart';
import 'command_dialog.dart';
import 'dialog_body.dart';
import 'controls.dart';
import 'fc_theme.dart';
import 'pick_list.dart';
import 'plate.dart';

/// Настройки списком: разделы модулей, под каждым — его поля.
///
/// Рисует одно место на всё приложение — модуль только перечисляет поля
/// ([SettingsSchema]). Отсюда и единообразие: `Tab` ходит одинаково, флаг
/// выглядит одинаково, а подпись «подействует со следующего запуска» стоит там
/// же, где и у соседа.
///
/// **Настройка — блок, а не строка формы:** подпись, объяснение, управление —
/// сверху вниз, по одной левой границе. Столбца подписей нет нарочно: с ним
/// подпись стояла бы справа, управление слева, а объяснение под управлением, и
/// читать приходилось бы по диагонали. Подробности и образец —
/// `docs/spec/settings-editor.md`.
///
/// **Слева оглавление** — заголовки разделов. Подсвечен тот, чьё начало сейчас
/// вверху обзора; щелчок прокручивает к разделу.
///
/// **Сверху поиск.** Отбирает по подписи, названию раздела, объяснению и ключу;
/// раздел, в котором ничего не совпало, пропадает и из списка, и из
/// оглавления.
///
/// Изменение применяется сразу и сразу же просит запись: кнопки «Применить»
/// нет, потому что отменять нечего — приложение и так живёт мгновенным
/// применением темы, колонок и скрытых файлов.
/// Подвал оглавления: ему дают, чем перечитать показанное.
typedef FcSettingsFooterBuilder = Widget Function(VoidCallback refresh);

class FcSettingsForm extends StatefulWidget {
  const FcSettingsForm({
    super.key,
    required this.pages,
    required this.onClose,
    this.searchHint = 'Search settings',
    this.footer,
  });

  final List<SettingsPage> pages;

  /// Закрыть — единственное действие окна.
  final VoidCallback onClose;

  /// Что написано в пустом поле поиска: форму берёт не одно окно настроек, и
  /// «Search settings» в окне клавиш обещало бы не то.
  final String searchHint;

  /// Что стоит в подвале оглавления; null — ничего.
  ///
  /// Подвал, а не поле среди настроек: «вернуть всё» относится к окну целиком,
  /// и среди настроек оно притворялось бы одной из них — да ещё и уезжало бы
  /// вместе с прокруткой и пропадало при отборе.
  ///
  /// Сборщиком, а не готовым виджетом: подвал меняет настройки **мимо полей**,
  /// и показанное после него надо перечитать — иначе в полях ввода останется
  /// набранное, которого в настройках уже нет.
  final FcSettingsFooterBuilder? footer;

  @override
  State<FcSettingsForm> createState() => _FcSettingsFormState();
}

class _FcSettingsFormState extends State<FcSettingsForm> {
  /// Насколько плавно оглавление уводит к разделу.
  ///
  /// Прыжком нельзя: человек щёлкнул по названию, а не «перенеси меня» — по
  /// движению видно, что список тот же самый и куда он уехал.
  static const Duration _scrollTo = Duration(milliseconds: 120);

  /// Схемы строятся один раз на язык, а не на каждый кадр: они держат
  /// замыкания к разделам, и пересобирать их без причины незачем. Причина одна
  /// — сменился язык: подписи полей схема несёт **строками**, а не способом их
  /// узнать, и на новом языке их надо спросить заново.
  ///
  /// Название раздела — это название модуля, и приходит оно английским: у
  /// модуля служб нет, а перевод его названия объявлен им самим
  /// (`docs/spec/localization.md`, §6).
  late List<(String, SettingsSchema)> _pages = _buildPages();

  /// Язык, на котором собраны [_pages].
  String? _language;

  List<(String, SettingsSchema)> _buildPages() => [
    for (final page in widget.pages) (context.strings.tr(page.title), page.build()),
  ];

  /// Заголовки разделов — по ключу на каждый: по ним считается, где раздел
  /// начинается, и для оглавления, и для прокрутки к нему.
  late final List<GlobalKey> _headings = [for (final _ in widget.pages) GlobalKey()];

  /// Поля ввода живут столько же, сколько окно: контроллер помнит набранное и
  /// положение курсора, а пересозданный терял бы и то и другое.
  final Map<String, TextEditingController> _editors = {};

  /// Строки списков — по полю; живут столько же, сколько окно, и по той же
  /// причине, что [_editors].
  ///
  /// Список строк **держится здесь, а не в настройке**: пустая строка, только
  /// что добавленная кнопкой «Add», значением ещё не стала — в настройку такая
  /// не попадает, а на экране стоять обязана, иначе нажатие осталось бы без
  /// ответа.
  final Map<String, _ListRows> _lists = {};

  final ScrollController _scroll = ScrollController();

  /// Набранное в поиске.
  final TextEditingController _query = TextEditingController();

  /// Узел поля поиска: по нему видно, оттуда ли нажали.
  ///
  /// Стрелки отдаются разделам только из поиска: в любом другом поле окна они
  /// водят курсор по набранному, и отбирать их у набора нельзя.
  final FocusNode _queryFocus = FocusNode(debugLabel: 'settings search');

  /// Что показано сейчас: номер раздела в [_pages], его заголовок, схема и
  /// поля, прошедшие отбор.
  ///
  /// Номер нужен ключам заголовков: они заведены на все разделы разом, а отбор
  /// оставляет не все.
  late List<(int, String, SettingsSchema, List<SettingsField>)> _found = [
    for (final (index, (title, schema)) in _pages.indexed) (index, title, schema, schema.fields),
  ];

  /// Раздел, подсвеченный в оглавлении, — номер в [_found].
  int _section = 0;

  /// Раздел, выбранный щелчком в оглавлении, — пока его держат.
  ///
  /// Без этого подсветка дёргается дважды. Прокрутка к разделу идёт плавно, и
  /// на каждом кадре под верхом обзора оказывается очередной раздел — подсветка
  /// пробегает по всем промежуточным, а оглавление уезжает следом за ней,
  /// потому что держит выбранное на виду. И это ещё не всё: раздел у самого низа
  /// до верха обзора вообще не доезжает, список упирается в конец, и подсветка
  /// возвращается на предыдущий — щелчок выглядит отменённым.
  ///
  /// Поэтому щелчок в оглавлении — это **намерение**, а не следствие
  /// геометрии: выбранное держится, пока человек сам не тронет список.
  int? _pinned;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
    _query.addListener(_onQuery);
  }

  /// Сменился язык — схемы пересобираются, а всё остальное остаётся: и
  /// набранное в поиске, и место, до которого долистали.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = context.strings.language;
    if (_language == language) {
      return;
    }
    _language = language;
    _pages = _buildPages();
    _refilter();
  }

  /// Пересобрать разделы: набор полей мог измениться.
  ///
  /// Схемы строятся один раз — они дороги не вычислением, а тем, что читают
  /// настройки. Но кнопка это **действие**, и действие вправе поменять состав
  /// полей: созданный набор обязан появиться в списке, не закрывая окна
  /// (`docs/spec/settings-presets.md`, §6). Набранное в поиске и в полях ввода
  /// переживает пересборку: поиск живёт своим контроллером, поля — своими, по
  /// ключу.
  void _rebuild() {
    _pages = _buildPages();
    // Значение могли сменить помимо окна — набором выбора или кнопкой подвала:
    // тогда показанное перечитывается. Согласное с настройкой не трогается,
    // иначе щелчок по чужому флажку сбрасывал бы курсор в соседнем поле.
    for (final (_, schema) in _pages) {
      for (final field in schema.fields) {
        _refreshEditor(field);
      }
    }
    _refilter();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    for (final editor in _editors.values) {
      editor.dispose();
    }
    for (final rows in _lists.values) {
      rows.dispose();
    }
    super.dispose();
  }

  /// Отбор по набранному.
  ///
  /// Подстрока, а не нечёткое совпадение: ключей человек не помнит, а слова из
  /// объяснения помнит точно. Совпало **название раздела** — раздел показан
  /// целиком: спросили «terminal», значит спросили про все его настройки, а не
  /// про те, у которых это слово ещё раз написано в подписи.
  void _onQuery() {
    _refilter();
    // Набрали новое — смотреть его надо сначала. При смене языка список
    // остаётся там, где стоял: человек не искал, он переключил язык.
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  /// Пересобрать показанное по тому, что набрано сейчас.
  void _refilter() {
    final query = _query.text.trim().toLowerCase();
    setState(() {
      _found = [
        for (final (index, (title, schema)) in _pages.indexed)
          if (query.isEmpty || title.toLowerCase().contains(query))
            (index, title, schema, schema.fields)
          else if (schema.fields.where((field) => _matches(field, query)).toList() case final fields
              when fields.isNotEmpty)
            (index, title, schema, fields),
      ];
      _section = 0;
      _pinned = null;
    });
  }

  static bool _matches(SettingsField field, String query) =>
      field.title.toLowerCase().contains(query) ||
      field.description.toLowerCase().contains(query) ||
      field.id.toLowerCase().contains(query) ||
      // Синонимы — то, чем вещь называют, но чего в подписи нет: «dark» у
      // смены темы. В строке их не видно, а найти по ним можно.
      field.keywords.any((word) => word.toLowerCase().contains(query));

  /// Где в строке стоит найденное — чтобы его выделить.
  List<int> _hits(String text) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) {
      return const [];
    }
    final at = text.toLowerCase().indexOf(query);
    return at < 0 ? const [] : [for (var i = 0; i < query.length; i++) at + i];
  }

  /// Ширина оглавления — по самому длинному названию раздела.
  ///
  /// Числом её не задать: по-русски названия длиннее английских, а у чужой темы
  /// ещё и шрифт другой. Метрика темы остаётся **нижней** границей — узкое
  /// оглавление рядом с широким списком читалось бы обрывком, — а верхняя не
  /// даёт ему съесть сами настройки.
  ///
  /// Меряются **все** разделы, а не только показанные: иначе оглавление
  /// дёргалось бы по ширине на каждую букву в поиске.
  ///
  /// Набор — тот же, каким список рисует выбранную строку: она жирная и потому
  /// самая широкая (`FcPickMark.weight`), и мерить по обычной значит промазать
  /// ровно на ней.
  double _tocWidth(BuildContext context, FcTheme theme, double dialogWidth, double outerPadding) {
    final metrics = theme.metrics;
    // Поле столбца снаружи списка, а внутри него текст отбит с обеих сторон:
    // считать надо всё три, иначе последняя буква упрётся в край.
    final around = outerPadding + 2 * metrics.dialogPadding;
    final needed =
        widestLabel(
          context,
          [for (final (title, _) in _pages) title],
          style: TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize, fontWeight: FontWeight.bold),
          limit: dialogWidth * _tocMaxShare - around,
        ) +
        around;
    return needed > metrics.settingsTocWidth ? needed : metrics.settingsTocWidth;
  }

  /// Больше сорока пяти сотых окна оглавление не занимает: за ним стоят сами
  /// настройки, и они здесь главные. Упёршись в предел, длинное название
  /// обрежется многоточием — так же, как обрезалось бы в любом списке.
  static const double _tocMaxShare = 0.45;

  /// Где начинается раздел, считая от начала прокрутки.
  ///
  /// Спрашивается у самой прокрутки, а не считается сложением просветов:
  /// высота блока зависит от того, как перенеслось объяснение, и повторить этот
  /// счёт в уме — верный способ разойтись с тем, что на экране.
  double? _startOf(int section) {
    final context = _headings[_found[section].$1].currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) {
      return null;
    }
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  }

  /// Какой раздел считать текущим.
  ///
  /// Тот, чьё начало последним осталось выше верха обзора. Исключение — самый
  /// низ списка: там короткий последний раздел не подсветить вовсе, и щелчок по
  /// нему в оглавлении оставался бы без отклика.
  int _sectionInView() {
    if (!_scroll.hasClients) {
      return 0;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      for (var i = _found.length - 1; i >= 0; i--) {
        final start = _startOf(i);
        if (start != null && start <= position.pixels + position.viewportDimension) {
          return i;
        }
      }
    }

    var current = 0;
    for (var i = 0; i < _found.length; i++) {
      final start = _startOf(i);
      if (start != null && start <= position.pixels + 1) {
        current = i;
      }
    }
    return current;
  }

  void _followScroll() {
    // Пока держим выбранное — за прокруткой не следим: она сейчас наша.
    if (_pinned != null) {
      return;
    }
    final current = _sectionInView();
    if (current != _section) {
      setState(() => _section = current);
    }
  }

  void _goToSection(int index) {
    final start = _startOf(index);
    if (start == null) {
      return;
    }
    _scroll.animateTo(start.clamp(0, _scroll.position.maxScrollExtent), duration: _scrollTo, curve: Curves.easeOut);
    setState(() {
      _section = index;
      _pinned = index;
    });
  }

  /// Тронули список — подсветка снова следит за прокруткой.
  void _unpin([Object? _]) {
    if (_pinned != null) {
      setState(() => _pinned = null);
      _followScroll();
    }
  }

  /// Клавиши окна поверх того, что делают сами поля
  /// (`docs/spec/settings-editor.md`, §9).
  ///
  /// Обработчик стоит **над** содержимым, а не в поле поиска: `PgUp` и `PgDn`
  /// листают список, откуда бы их ни нажали — в поле ввода они не значат
  /// ничего, а «полистать читаемое» значат всегда.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp) {
      _page(forward: key == LogicalKeyboardKey.pageDown);
      return KeyEventResult.handled;
    }
    // Дальше — только из поиска: там стрелки свободны (строка одна), а в
    // прочих полях они водят курсор.
    if (!_queryFocus.hasFocus || _found.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _goToSection((_section + 1).clamp(0, _found.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _goToSection((_section - 1).clamp(0, _found.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Страница списка настроек.
  ///
  /// Обзором, а не числом строк: блоки разной высоты, и «десять строк» здесь
  /// значило бы разное в каждом разделе. Удержание при этом снимается —
  /// подсветка в оглавлении снова следит за прокруткой: листают тут
  /// **читаемое**, а не выбирают раздел.
  void _page({required bool forward}) {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final step = forward ? position.viewportDimension : -position.viewportDimension;
    final target = (position.pixels + step).clamp(position.minScrollExtent, position.maxScrollExtent);
    _unpin();
    position.animateTo(target, duration: _scrollTo, curve: Curves.easeOut);
  }

  TextEditingController _editorFor(String id, String initial) =>
      _editors.putIfAbsent(id, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    final padding = dialogContentPadding(context);
    final width = MediaQuery.sizeOf(context).width * metrics.settingsWidthFactor;

    return Focus(
      // Только слушатель: фокуса не берёт и в обход `Tab` не встаёт — клавиши
      // окна ловятся по дороге наверх от того поля, где фокус сейчас.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: SizedBox(
        // Своя доля, шире прочих окон: колонок здесь две, и обе с текстом.
        width: width,
        child: ConstrainedBox(
          // Предел по высоте — то же правило, что у справки: без него прокрутка
          // не работает, `Flexible` получает бесконечность, и форма вылезает за
          // экран.
          constraints: dialogContentLimits(context),
          // Тело окна: содержимое, под ним ряд кнопок, прибитый к низу
          // (`docs/spec/dialog-body.md`). Листает себя окно само — колонками, у
          // каждой своя прокрутка, — и поля ставит там же, внутри них.
          child: FcDialogBody(
            scrolls: false,
            insets: FcDialogInsets.none,
            // Кнопки нет вовсе: настройки применяются сразу, закрывают окно
            // `Esc` и крестик в заголовке, а ряд внизу стоил бы списку целой
            // полосы высоты. Без кнопок ряд схлопывается сам
            // (`docs/spec/dialog-body.md`).
            actions: const [],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Заданную высоту колонка отдаёт своему ряду: под растянутым окном
              // список должен дотянуться до кнопок, а не оставить полосу пустоты.
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  // Растяжкой, а не по содержимому: обе колонки прокручиваются
                  // сами, и высоту им должен задать ряд, иначе мерить её будет
                  // нечем.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _tocWidth(context, theme, width, padding.left),
                        child: Padding(
                          padding: EdgeInsets.only(left: padding.left, top: padding.top, bottom: padding.bottom),
                          // Поле поиска стоит **в этом столбце**, а не над обоими:
                          // оно отбирает разделы, и место ему там же, где они. А
                          // список настроек получает всю высоту окна и начинает
                          // прокручиваться от самого верха.
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FcTextField(
                                controller: _query,
                                focusNode: _queryFocus,
                                autofocus: true,
                                hintText: context.strings.tr(widget.searchHint),
                              ),
                              // Счёт — только пока отбирают: «22 settings» при
                              // пустом поле отвечает на вопрос, которого никто не
                              // задавал, а вот «5 settings» объясняет, почему
                              // список вдруг короткий.
                              if (_query.text.trim().isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: metrics.dialogLineGap, left: metrics.dialogPadding),
                                  child: Text(_countLabel, style: _secondaryStyle(theme)),
                                ),
                              SizedBox(height: metrics.dialogGap),
                              // Пустого оглавления не бывает: «ничего не нашлось»
                              // сказано один раз, справа, а пустой список сказал
                              // бы то же самое вторично.
                              if (_found.isNotEmpty)
                                Expanded(
                                  child: FcPickList(
                                    rows: [for (final (_, title, _, _) in _found) FcPickRow(id: title, title: title)],
                                    // Оглавление отбирают снаружи, а не изнутри:
                                    // раздел, в котором ничего не совпало, из него
                                    // уже пропал, и подсвечивать в оставшихся
                                    // нечего.
                                    query: '',
                                    // Свой отступ: по умолчанию строка списка
                                    // равняется по тексту в поле ввода над ней, а
                                    // здесь поле стоит вплотную — и равняться надо
                                    // по нему.
                                    textInset: metrics.dialogPadding,
                                    selected: _section,
                                    // Оглавление не выбирают — оно показывает, где
                                    // вы сейчас, и курсору здесь не обо что
                                    // упереться: ни рамки, ни фона у столбца нет.
                                    mark: FcPickMark.weight,
                                    onTap: (id) => _goToSection(_found.indexWhere((section) => section.$2 == id)),
                                  ),
                                ),
                              // Подвал прижат к низу столбца: место ему там же,
                              // где разделы, но отдельно от них.
                              // Ничего не нашлось — оглавления нет, а подвал
                              // остаётся внизу: иначе он убегал бы под поле
                              // поиска на каждый запрос, которому нечего
                              // показать.
                              if (_found.isEmpty) const Spacer(),
                              if (widget.footer case final footer?) ...[
                                SizedBox(height: metrics.dialogGap),
                                // Слева и по содержимому: столбец растягивает
                                // детей, и кнопка иначе разъехалась бы на всю
                                // его ширину. `scaleDown` — на случай узкого
                                // столбца: ширину ему задают названия разделов,
                                // и подпись подвала бывает длиннее их всех. Тем
                                // же приёмом ужимается ряд кнопок окна
                                // (`FcDialogActions`).
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: footer(_rebuild),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                            _found.isEmpty
                                ? Center(
                                  child: Text(context.strings.tr('Nothing found'), style: theme.dialogLabelStyle),
                                )
                                // Любое касание списка снимает удержание: колесо,
                                // перетаскивание полосы, щелчок по настройке.
                                : Listener(
                                  onPointerDown: _unpin,
                                  onPointerSignal: _unpin,
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    // Поля — **внутри** прокрутки, все четыре: так
                                    // список начинается от края окна и уезжает под
                                    // заголовок целиком, а не упирается в его
                                    // тень. Тем же приёмом живут сведения и сетка
                                    // значков в панели.
                                    padding: padding,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        for (final (position, (index, title, schema, fields)) in _found.indexed) ...[
                                          // Просвет **перед** заголовком, а не
                                          // после каждого раздела: у первого
                                          // сверху уже есть поле окна. Равен полю
                                          // окна по бокам — тем же, каким отбиты
                                          // плашки в справке.
                                          if (position > 0) SizedBox(height: metrics.dialogHorizontalPadding),
                                          FcPlate(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                _heading(theme, title, key: _headings[index]),
                                                for (final (at, field) in fields.indexed) ...[
                                                  // Линейка **между** настройками,
                                                  // а не под каждой: края раздела
                                                  // рисует плашка вокруг него, и
                                                  // линейка по её кромке была бы
                                                  // второй границей на том же
                                                  // месте. То же правило у
                                                  // таблицы справки, и линейка та
                                                  // же — иначе соседние настройки
                                                  // читаются одним сплошным
                                                  // столбцом.
                                                  if (at > 0) ...[
                                                    SizedBox(height: metrics.sectionEntryGap),
                                                    Container(
                                                      height: metrics.strokeWidth,
                                                      color: theme.colors.columnDivider,
                                                    ),
                                                  ],
                                                  // Над подписью просвет **меньше**
                                                  // на пустоту, которую строка
                                                  // текста несёт над буквами: равные
                                                  // числа дают неравные просветы, и
                                                  // настройка стояла бы ближе к
                                                  // своей линейке снизу, чем к
                                                  // чужой сверху
                                                  // (`docs/spec/settings-editor.md`,
                                                  // §12).
                                                  SizedBox(height: metrics.sectionEntryGap - metrics.fontCapInset),
                                                  _block(theme, schema, field),
                                                ],
                                                // До кромки плашки — столько же,
                                                // сколько до линейки: своего поля у
                                                // плашки меньше, и последняя
                                                // настройка липла к её нижнему краю.
                                                SizedBox(height: metrics.sectionEntryGap - metrics.dialogPadding),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Сколько настроек осталось после отбора.
  String get _countLabel {
    final count = _found.fold(0, (sum, section) => sum + section.$4.length);
    return count == 1 ? '1 setting' : '$count settings';
  }

  /// Раздел настроек — в плашке, той же, какой обведён список находок и
  /// разделы справки (`docs/widgets.md`).
  ///
  /// Разделов в окне много, и сплошной лентой они читаются хуже: плашка даёт
  /// глазу, где раздел начался и где кончился, — а заодно окно настроек и
  /// справка перестают выглядеть по-разному.
  /// Заголовок раздела.
  ///
  /// Крупнее остального текста, а не только жирнее: это единственное, что
  /// говорит, чьи это настройки, — приставки с названием модуля у подписей нет.
  Widget _heading(FcTheme theme, String title, {Key? key}) => Padding(
    // По той же левой границе, что и настройки: под ними стоит место под
    // полосу пометки, и без отступа заголовок висел бы левее столбца.
    padding: EdgeInsets.only(left: theme.metrics.markedBarWidth + theme.metrics.columnGap),
    child: Text(
      title,
      key: key,
      style: TextStyle(
        fontFamily: theme.fonts.ui,
        fontSize: theme.metrics.sectionHeadingFontSize,
        fontWeight: FontWeight.bold,
        color: theme.colors.dialogTitleText,
      ),
    ),
  );

  /// Подпись настройки: «*Категория:* **Имя**».
  ///
  /// Категория — название модуля, тем же цветом, что и объяснения. Она стоит
  /// всегда, хотя заголовок раздела виден рядом: одинаковые подписи у разных
  /// модулей иначе неразличимы — «Wrap long lines» есть и у редактора, и у
  /// просмотрщика текста.
  /// Подпись настройки.
  ///
  /// Без приставки с названием модуля: раздел всегда идёт под своим
  /// заголовком — и при отборе тоже, — поэтому в каждой строке она была не
  /// уточнением, а шумом. Отличать «Wrap long lines» редактора от такого же у
  /// просмотрщика текста берётся заголовок, а не двадцать повторов над ним.
  InlineSpan _titleSpan(FcTheme theme, String title) =>
      TextSpan(children: _marked(theme, title, _labelStyle(theme).copyWith(fontWeight: FontWeight.bold)));

  /// Текст с выделенным найденным.
  ///
  /// Выделяется подложкой, а не жирным, как в палитре: имя настройки и так
  /// набрано жирным, и выделить его тем же нечем.
  ///
  /// Нужно оно здесь по той же причине, что и там, только повод другой: в
  /// палитре непонятно, почему строка нашлась (`cpf` в `Copy File`), а тут —
  /// **где** она нашлась. Настройка, совпавшая объяснением или ключом, иначе
  /// выглядит попавшей в список случайно.
  List<TextSpan> _marked(FcTheme theme, String text, TextStyle style) =>
      highlightMatch(text, _hits(text), style, matched: style.copyWith(backgroundColor: theme.colors.markedBackground));

  /// Настройка целиком: подпись, объяснение, оговорка, управление.
  ///
  /// У флага порядок другой: квадрат встаёт **на строку подписи**, потому что у
  /// него подпись и есть управление. Поставь его как у всех — и подпись
  /// повторилась бы дважды: заголовком и меткой рядом с квадратом.
  Widget _block(FcTheme theme, SettingsSchema schema, SettingsField field) {
    final metrics = theme.metrics;
    // Тронутое видно полосой слева — тем же цветом, каким помечена строка в
    // панели: «это тронуто» в приложении уже значит именно это. Место под
    // полосу занято всегда, иначе подписи ездили бы вправо-влево на каждую
    // правку.
    final touched = !field.isDefault;
    final explanations = [
      if (field.description.isNotEmpty)
        Text.rich(TextSpan(children: _marked(theme, field.description, _secondaryStyle(theme)))),
      // Оговорка отдельной строкой и другим цветом: это не объяснение, а
      // предупреждение — «сейчас ничего не произойдёт».
      if (field.note.isNotEmpty)
        Text(field.note, style: _secondaryStyle(theme).copyWith(color: theme.colors.secondaryText)),
    ];

    // Клавиша — справа, в одну строку с названием: читают этот список
    // названиями, а клавиша при каждом из них стоит столбцом.
    if (field is SettingsKeys) {
      return _withMarker(
        theme,
        touched,
        Row(
          // Кнопка равняется по **первой** строке: название с объяснением
          // бывает в две строки, и по середине она уехала бы вниз.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Название и объяснение — одним столбцом, и уже он встаёт в ряд с
            // кнопкой. Порознь ряд задал бы им свою высоту, и межстрочный
            // просвет разъехался бы по строке названия.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // «Reset» прижат к названию, как у всех прочих настроек: он
                  // про **эту** настройку, и место ему при её подписи, а не у
                  // дальнего края рядом с чужой кнопкой.
                  _titleLine(theme, schema, field, Text.rich(_titleSpan(theme, field.title))),
                  for (final line in explanations) ...[SizedBox(height: metrics.dialogLineGap), line],
                ],
              ),
            ),
            SizedBox(width: metrics.columnGap),
            _control(theme, schema, field),
          ],
        ),
      );
    }

    if (field is SettingsFlag) {
      return _withMarker(
        theme,
        touched,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleLine(theme, schema, field, _control(theme, schema, field)),
            // Объяснение равняется по подписи, а не по квадрату: оно относится
            // к настройке, а не к галочке.
            if (explanations.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: metrics.dialogLineGap, left: metrics.checkboxSize + metrics.checkboxGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: explanations,
                ),
              ),
          ],
        ),
      );
    }

    return _withMarker(
      theme,
      touched,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _titleLine(theme, schema, field, Text.rich(_titleSpan(theme, field.title))),
          for (final line in explanations) ...[SizedBox(height: metrics.dialogLineGap), line],
          SizedBox(height: metrics.dialogLineGap),
          _control(theme, schema, field),
        ],
      ),
    );
  }

  /// Блок с полосой слева — или с пустым местом той же ширины.
  ///
  /// Полоса — рамкой, а не соседом в ряду: сосед не знает высоты блока, а
  /// растягивать его нечем — блок стоит в прокрутке, и высота там не задана.
  /// Рамка же ровно такой высоты, какой вышел блок.
  Widget _withMarker(FcTheme theme, bool touched, Widget block) {
    final metrics = theme.metrics;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            // Прозрачная, но той же ширины: иначе подписи ездили бы
            // вправо-влево на каждую правку.
            color: touched ? theme.colors.markedBar : const Color(0x00000000),
            width: metrics.markedBarWidth,
          ),
        ),
      ),
      padding: EdgeInsets.only(left: metrics.columnGap),
      child: block,
    );
  }

  /// Строка подписи: сама подпись (у флага — вместе с квадратом) и «Reset».
  ///
  /// «Reset» появляется только у тронутого: у настройки, стоящей на умолчании,
  /// он предлагал бы ничего не делать.
  Widget _titleLine(FcTheme theme, SettingsSchema schema, SettingsField field, Widget title) {
    if (field.isDefault) {
      return title;
    }
    return Row(
      children: [Flexible(child: title), SizedBox(width: theme.metrics.columnGap), _reset(theme, schema, field)],
    );
  }

  /// Показать в поле ввода то, что стоит в настройке сейчас.
  ///
  /// Нужно после возврата к умолчанию: контроллер живёт столько же, сколько
  /// окно, и о том, что значение сменилось помимо набора, сам не узнает —
  /// пометка снималась бы, а в поле оставалось набранное.
  void _refreshEditor(SettingsField field) {
    if (field is SettingsList) {
      _lists[field.id]?.syncTo(field.read());
      return;
    }
    final editor = _editors[field.id];
    if (editor == null) {
      return;
    }
    final value = switch (field) {
      SettingsNumber number => '${number.read()}',
      SettingsDecimal decimal => '${decimal.read()}',
      SettingsColor color => formatColor(color.read()),
      SettingsText text => text.read(),
      _ => null,
    };
    // Согласное с настройкой не трогается: перестановка того же текста увела
    // бы курсор в конец строки посреди набора.
    if (value != null && value != editor.text) {
      editor.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    }
  }

  Widget _reset(FcTheme theme, SettingsSchema schema, SettingsField field) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () {
        field.resetToDefault();
        _refreshEditor(field);
        schema.save();
        setState(() {});
      },
      child: Text(context.strings.tr('Reset'), style: _secondaryStyle(theme).copyWith(color: theme.colors.markedBar)),
    ),
  );

  /// Флажок, а рядом — его кнопка, если она есть.
  ///
  /// Кнопка живая и при снятом флажке: отказ делать по расписанию не значит
  /// отказа сделать сейчас (`docs/spec/self-update.md`, §8).
  Widget _flagControl(FcTheme theme, SettingsFlag flag, VoidCallback changed) {
    final checkbox = FcCheckbox(
      label: flag.title,
      richLabel: _titleSpan(theme, flag.title),
      value: flag.read(),
      onChanged: (value) {
        flag.write(value);
        changed();
      },
    );

    final action = flag.action;
    if (action == null) {
      return checkbox;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Уступает флажок, а не кнопка: подпись длинная и ужимается, а кнопка
        // облегает своё слово и гнуться ей нечем.
        Flexible(child: checkbox),
        SizedBox(width: theme.metrics.dialogGap),
        _actionButton(action),
      ],
    );
  }

  /// Кнопка-приставка: ждёт ответа и пересобирает разделы — действие вправе
  /// поменять набор полей (см. [_rebuild]).
  Widget _actionButton(SettingsAction action) => FcButton(
    label: action.label,
    onPressed:
        action.run == null
            ? null
            : () async {
              await action.run!();
              if (mounted) {
                _rebuild();
              }
            },
  );

  /// Строки списка одна под другой, у каждой «×», внизу «Add».
  ///
  /// Строка во всю ширину, а «×» столбцом у правого края: значения тут
  /// однородны, и убирают их обычно подряд — по столбцу целиться проще, чем по
  /// крестику, гуляющему за концом каждой строки.
  Widget _listControl(FcTheme theme, SettingsList field, VoidCallback changed) {
    final metrics = theme.metrics;
    final rows = _rowsFor(field);

    // Пустая строка значением не считается: пока в ней ничего не набрано,
    // настройке о ней знать нечего — но на экране она стоит (см. [_lists]).
    void store() {
      field.write(rows.values);
      changed();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in rows.rows.indexed) ...[
          if (index > 0) SizedBox(height: metrics.dialogLineGap),
          Row(
            children: [
              Expanded(
                child: FcTextField(
                  controller: row.editor,
                  focusNode: row.focus,
                  hintText: field.hint,
                  onChanged: (_) => store(),
                  // `Enter` в строке — то же, что «Add»: список набирают
                  // подряд, и тянуться за кнопкой после каждого значения
                  // незачем.
                  onSubmitted: (_) => _addRow(field, rows),
                ),
              ),
              SizedBox(width: metrics.columnGap),
              _removeRow(theme, () {
                rows.removeAt(index);
                store();
              }),
            ],
          ),
        ],
        SizedBox(height: metrics.dialogLineGap),
        // Ряд с `min` — чтобы кнопка облегала свою подпись, как все кнопки
        // приложения.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [FcButton(label: context.strings.tr('Add'), onPressed: () => _addRow(field, rows))],
        ),
      ],
    );
  }

  /// Строки этого поля; в первый раз — по тому, что в настройке стоит сейчас.
  _ListRows _rowsFor(SettingsList field) => _lists.putIfAbsent(field.id, () => _ListRows(field.read()));

  /// Пустая строка внизу и курсор в ней.
  ///
  /// Курсор — потому что добавить строку и значит начать набирать: без него
  /// нажатие выглядело бы так, будто ничего не произошло. Настройка при этом
  /// не трогается — пустой строке в ней места нет.
  void _addRow(SettingsList field, _ListRows rows) {
    setState(rows.add);
    // После кадра: узла фокуса у новой строки до её сборки ещё нет.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        rows.rows.last.focus.requestFocus();
      }
    });
  }

  /// «×» — убрать строку.
  ///
  /// Знаком, а не иконкой: так же убирают работу из списка фоновых
  /// (`background_tasks_view.dart`), и заводить ради этого глиф в наборе
  /// иконок незачем.
  Widget _removeRow(FcTheme theme, VoidCallback pressed) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: pressed,
      child: Text('✕', style: _secondaryStyle(theme).copyWith(color: theme.colors.dialogText)),
    ),
  );

  Widget _control(FcTheme theme, SettingsSchema schema, SettingsField field) {
    void changed() {
      schema.save();
      setState(() {});
    }

    // Правка выбора и флажка меняет не только себя: от неё зависит, что
    // **могут** соседи — выбранный набор оживляет «Update» и «Delete», и без
    // пересборки они остались бы приглушёнными до следующего открытия окна.
    // Набор при этом меняется редко, а набранное в полях ввода пересборку
    // переживает: контроллеры живут по ключу поля.
    void switched() {
      schema.save();
      _rebuild();
    }

    return switch (field) {
      SettingsFlag flag => _flagControl(theme, flag, switched),
      // Кнопка стоит одна, без поля: у неё нет значения, которое можно было бы
      // показать рядом. Ряд с `min` — чтобы она облегала свою подпись, как и
      // все кнопки приложения (`FcDialogActions`).
      SettingsButton button => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FcButton(
            label: button.label,
            onPressed:
                button.run == null
                    ? null
                    : () async {
                      await button.run!();
                      if (mounted) {
                        _rebuild();
                      }
                    },
          ),
        ],
      ),
      // Клавиша — тоже кнопка, и написано на ней то, чем команду вызывают:
      // ради этого окно и открывают. Нет клавиши — прочерк, а не пустая
      // кнопка: пустую не за что нажать глазами.
      SettingsKeys keys => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FcButton(
            label: keys.read().isEmpty ? '—' : keys.read(),
            onPressed: () async {
              await keys.edit();
              if (mounted) {
                changed();
              }
            },
          ),
        ],
      ),
      // Выпадающим списком, а не переключателем: темы приносят модули, и
      // строка на каждый вариант росла бы вместе с их числом.
      SettingsChoice choice => Wrap(
        // Одной строкой со списком: кнопки — про то, что в нём выбрано, и
        // отдельной строкой читались бы как своё, отдельное дело. `Wrap` —
        // чтобы в узком окне ряд переносился, а не лез за край.
        spacing: theme.metrics.dialogGap,
        runSpacing: theme.metrics.dialogLineGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FcSelect<String>(
            options: choice.options,
            value: choice.read(),
            onChanged: (value) {
              choice.write(value);
              switched();
            },
          ),
          for (final action in choice.actions) _actionButton(action),
        ],
      ),
      SettingsNumber number => Row(
        children: [
          // Поле числа короткое — числа коротки, — но уступает, когда окно
          // узко: иначе единица измерения рядом с ним вылезает за край.
          Flexible(
            child: SizedBox(
              width: theme.metrics.dialogLabelWidth,
              child: FcTextField(
                controller: _editorFor(number.id, '${number.read()}'),
                // Набранное, которое числом не является, просто не применяется:
                // ругаться на «сто» посреди набора хуже, чем подождать, пока
                // человек допишет.
                onChanged: (value) {
                  final parsed = number.parse(value);
                  if (parsed != null) {
                    number.write(parsed);
                    // Через `changed`, а не просто записью: набранное могло
                    // сойти с умолчания или вернуться на него, и пометка с
                    // «Reset» должны появиться сразу, а не с чужой перерисовки.
                    changed();
                  }
                },
              ),
            ),
          ),
          if (number.unit.isNotEmpty) ...[
            SizedBox(width: theme.metrics.columnGap),
            Text(number.unit, style: _labelStyle(theme)),
          ],
        ],
      ),
      // Дробное — тем же полем, что и целое: разнится у них разбор
      // набранного, а не вид (`docs/spec/theme-editor.md`, §4).
      SettingsDecimal decimal => Row(
        children: [
          Flexible(
            child: SizedBox(
              width: theme.metrics.dialogLabelWidth,
              child: FcTextField(
                controller: _editorFor(decimal.id, '${decimal.read()}'),
                onChanged: (value) {
                  final parsed = decimal.parse(value);
                  if (parsed != null) {
                    decimal.write(parsed);
                    changed();
                  }
                },
              ),
            ),
          ),
          if (decimal.unit.isNotEmpty) ...[
            SizedBox(width: theme.metrics.columnGap),
            Text(decimal.unit, style: _labelStyle(theme)),
          ],
        ],
      ),
      // Цвет — образцом и полем: набирают его руками, а узнают в лицо.
      SettingsColor color => FcColorField(
        controller: _editorFor(color.id, formatColor(color.read())),
        value: color.read(),
        palette: color.palette,
        fieldWidth: theme.metrics.dialogLabelWidth,
        onChanged: (value) {
          color.write(value);
          changed();
        },
      ),
      SettingsList list => _listControl(theme, list, changed),
      SettingsText text => FcTextField(
        controller: _editorFor(text.id, text.read()),
        hintText: text.hint,
        onChanged: (value) {
          text.write(value);
          changed();
        },
      ),
    };
  }

  TextStyle _labelStyle(FcTheme theme) =>
      TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, color: theme.colors.dialogText);

  TextStyle _secondaryStyle(FcTheme theme) =>
      TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, color: theme.colors.dialogLabel);
}

/// Строки одного списка настроек: поле ввода и его фокус на каждую.
///
/// Живут в окне, а не в настройке: пустая строка, только что добавленная
/// кнопкой «Add», значением ещё не стала — в настройку она не попадает, а на
/// экране стоять обязана (`docs/spec/settings-editor.md`, §8).
class _ListRows {
  _ListRows(List<String> values) {
    _fill(values);
  }

  final List<_ListRow> rows = [];

  /// Что из этого — значения: набранное без пустых строк.
  ///
  /// Пробелы по краям срезаются здесь, а не при наборе: срезать их на каждую
  /// букву значило бы не дать напечатать пробел внутри значения.
  List<String> get values => [
    for (final row in rows)
      if (row.editor.text.trim().isNotEmpty) row.editor.text.trim(),
  ];

  void add() => rows.add(_ListRow());

  void removeAt(int index) => rows.removeAt(index).dispose();

  /// Собрать заново, если настройка разошлась со строками.
  ///
  /// Разойтись она может «Reset»-ом и набором выбора. Пока они согласны,
  /// строки не трогаются — пустая только что добавленная останется на месте, а
  /// курсор в набираемой строке не прыгнет в начало.
  void syncTo(List<String> stored) {
    final shown = values;
    if (shown.length == stored.length) {
      var same = true;
      for (var i = 0; i < shown.length; i++) {
        if (shown[i] != stored[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    for (final row in rows) {
      row.dispose();
    }
    rows.clear();
    _fill(stored);
  }

  void _fill(List<String> values) {
    for (final value in values) {
      rows.add(_ListRow(value));
    }
  }

  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    rows.clear();
  }
}

class _ListRow {
  _ListRow([String value = '']) : editor = TextEditingController(text: value);

  final TextEditingController editor;
  final FocusNode focus = FocusNode(debugLabel: 'settings list row');

  void dispose() {
    editor.dispose();
    focus.dispose();
  }
}
