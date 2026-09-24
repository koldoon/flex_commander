import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'command_dialog.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

/// Раздел для [FcIndexedSections]: название в оглавлении и он сам.
class FcIndexedSection {
  const FcIndexedSection({required this.title, required this.child, String? id}) : _id = id;

  /// Название: им раздел назван в оглавлении, и по нему же считается ширина
  /// столбца.
  final String title;

  /// Сам раздел — с заголовком, плашкой и всем прочим: рисует его тот, кто
  /// знает, из чего раздел состоит.
  final Widget child;

  final String? _id;

  /// Чем раздел опознаётся между сборками; по умолчанию — название.
  String get id => _id ?? title;
}

/// Что стоит в подвале оглавления; [refresh] пересобирает показанное.
typedef FcSectionsFooter = Widget Function(VoidCallback refresh);

/// Длинное содержимое с **оглавлением слева и поиском над ним**.
///
/// Одно место на всё приложение: так устроены окно настроек, окно клавиш,
/// редактор тем и справка (`docs/spec/help-window.md`, §2). Второй такой же
/// сайдбар написался бы быстрее, но решения тут куплены дорого — удержание
/// выбранного раздела, мерка начала раздела у самой прокрутки, ширина столбца
/// по жирному набору, — и разойтись двум копиям было бы делом одного этапа.
///
/// **Слева оглавление** — названия разделов. Подсвечен тот, чьё начало сейчас
/// вверху обзора; щелчок прокручивает к разделу.
///
/// **Сверху поиск.** Что именно ищется — дело того, кто даёт разделы: [sections]
/// зовётся с набранным, и отбор остаётся у него. Раздел, которого в ответе нет,
/// пропадает и из списка, и из оглавления.
class FcIndexedSections extends StatefulWidget {
  const FcIndexedSections({
    super.key,
    required this.sections,
    required this.titles,
    this.searchHint = 'Search',
    this.countLabel,
    this.footer,
    this.emptyLabel = 'Nothing found',
  });

  /// Разделы под набранное; пустая строка — показать всё.
  final List<FcIndexedSection> Function(String query) sections;

  /// Названия **всех** разделов, а не показанных: ими меряется ширина
  /// оглавления, и без этого оно дёргалось бы на каждую букву в поиске.
  final List<String> titles;

  /// Что написано в пустом поле поиска: форму берёт не одно окно, и «Search
  /// settings» в справке обещало бы не то.
  final String searchHint;

  /// Сколько нашлось — строкой под полем поиска, и только пока отбирают.
  ///
  /// Считает тот, кто даёт разделы: у настроек это поля, у справки — строки, а
  /// число разделов не говорит ни о том, ни о другом. Спрашивается с тем же
  /// запросом, каким собраны разделы.
  final String Function(String query)? countLabel;

  /// Что стоит в подвале оглавления; null — ничего.
  final FcSectionsFooter? footer;

  /// Что сказать, когда не нашлось ничего.
  final String emptyLabel;

  @override
  State<FcIndexedSections> createState() => _FcIndexedSectionsState();
}

class _FcIndexedSectionsState extends State<FcIndexedSections> {
  /// Насколько плавно оглавление уводит к разделу.
  ///
  /// Прыжком нельзя: человек щёлкнул по названию, а не «перенеси меня» — по
  /// движению видно, что список тот же самый и куда он уехал.
  static const Duration _scrollTo = Duration(milliseconds: 120);

  /// Больше сорока пяти сотых окна оглавление не занимает: за ним стоит само
  /// содержимое, и оно здесь главное. Упёршись в предел, длинное название
  /// обрежется многоточием — так же, как обрезалось бы в любом списке.
  static const double _tocMaxShare = 0.45;

  final ScrollController _scroll = ScrollController();

  /// Набранное в поиске.
  final TextEditingController _query = TextEditingController();

  /// Узел поля поиска: по нему видно, оттуда ли нажали.
  ///
  /// Стрелки отдаются разделам только из поиска: в любом другом поле окна они
  /// водят курсор по набранному, и отбирать их у набора нельзя.
  final FocusNode _queryFocus = FocusNode(debugLabel: 'sections search');

  /// Плашки разделов — по ключу на каждый: по ним считается, где раздел
  /// начинается, и для оглавления, и для прокрутки к нему.
  final Map<String, GlobalKey> _plates = {};

  /// Раздел, подсвеченный в оглавлении, — номер среди показанных.
  ///
  /// Записка, а не поле состояния: меняется она на каждой прокрутке, а
  /// перерисовать от неё надо **одно оглавление**. Через `setState` за ней
  /// пересобиралось бы всё содержимое — полторы сотни блоков редактора тем
  /// разом.
  final ValueNotifier<int> _section = ValueNotifier(0);

  /// Раздел, выбранный щелчком, — пока его держат.
  ///
  /// Без этого подсветка дёргается дважды. Прокрутка к разделу идёт плавно, и
  /// на каждом кадре под верхом обзора оказывается очередной раздел — подсветка
  /// пробегает по всем промежуточным, а оглавление уезжает следом за ней.
  /// И это ещё не всё: раздел у самого низа до верха обзора вообще не доезжает,
  /// список упирается в конец, и подсветка возвращается на предыдущий — щелчок
  /// выглядит отменённым.
  ///
  /// Поэтому щелчок в оглавлении — это **намерение**, а не следствие геометрии:
  /// выбранное держится, пока человек сам не тронет содержимое.
  int? _pinned;

  /// Показанное на этой сборке: им пользуются клавиши и оглавление.
  List<FcIndexedSection> _shown = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
    _query.addListener(_onQuery);
  }

  @override
  void dispose() {
    _section.dispose();
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Набрали новое — смотреть его надо сначала.
  void _onQuery() {
    setState(() => _pinned = null);
    _section.value = 0;
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  /// Пересобрать показанное: состав разделов мог измениться помимо поиска —
  /// кнопкой подвала, например.
  void _refresh() => setState(() {});

  GlobalKey _plateOf(String id) => _plates.putIfAbsent(id, GlobalKey.new);

  /// Ширина оглавления — по самому длинному названию раздела.
  ///
  /// Числом её не задать: по-русски названия длиннее английских, а у чужой темы
  /// ещё и шрифт другой. Метрика темы остаётся **нижней** границей — узкое
  /// оглавление рядом с широким содержимым читалось бы обрывком, — а верхняя не
  /// даёт ему съесть само содержимое.
  ///
  /// Набор — тот же, каким список рисует выбранную строку: она жирная и потому
  /// самая широкая (`FcPickMark.weight`), и мерить по обычной значит промазать
  /// ровно на ней.
  double _tocWidth(BuildContext context, FcTheme theme, double paneWidth, double outerPadding) {
    final metrics = theme.metrics;
    // Поле столбца снаружи списка, а внутри него текст отбит с обеих сторон:
    // считать надо всё три, иначе последняя буква упрётся в край.
    final around = outerPadding + 2 * metrics.dialogPadding;
    final needed =
        widestLabel(
          context,
          widget.titles,
          style: TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize, fontWeight: FontWeight.bold),
          limit: paneWidth * _tocMaxShare - around,
        ) +
        around;
    return needed > metrics.settingsTocWidth ? needed : metrics.settingsTocWidth;
  }

  /// Где начинается раздел, считая от начала прокрутки.
  ///
  /// Спрашивается у самой прокрутки, а не считается сложением просветов:
  /// высота раздела зависит от того, как перенеслись его строки, и повторить
  /// этот счёт в уме — верный способ разойтись с тем, что на экране.
  double? _startOf(int section) {
    if (section < 0 || section >= _shown.length) {
      return null;
    }
    final context = _plateOf(_shown[section].id).currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) {
      return null;
    }
    // Минус поле списка сверху: плашка встаёт туда же, где стоит первая при
    // нетронутой прокрутке, — вровень с полем поиска слева.
    final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    return reveal - dialogContentPadding(this.context).top;
  }

  /// Какой раздел считать текущим.
  ///
  /// Тот, чьё начало последним осталось выше верха обзора. Исключение — самый
  /// низ: там короткий последний раздел не подсветить вовсе, и щелчок по нему в
  /// оглавлении оставался бы без отклика.
  int _sectionInView() {
    if (!_scroll.hasClients) {
      return 0;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      for (var i = _shown.length - 1; i >= 0; i--) {
        final start = _startOf(i);
        if (start != null && start <= position.pixels + position.viewportDimension) {
          return i;
        }
      }
    }

    var current = 0;
    for (var i = 0; i < _shown.length; i++) {
      final start = _startOf(i);
      if (start == null) {
        continue;
      }
      // Разделы идут сверху вниз, и начала у них растут: первый, что ушёл ниже
      // верха обзора, заканчивает поиск.
      if (start > position.pixels + 1) {
        break;
      }
      current = i;
    }
    return current;
  }

  void _followScroll() {
    // Пока держим выбранное — за прокруткой не следим: она сейчас наша.
    if (_pinned != null) {
      return;
    }
    _section.value = _sectionInView();
  }

  void _goToSection(int index) {
    final start = _startOf(index);
    if (start == null) {
      return;
    }
    _scroll.animateTo(start.clamp(0, _scroll.position.maxScrollExtent), duration: _scrollTo, curve: Curves.easeOut);
    // Ни то ни другое в сборке не участвует: подсветку показывает оглавление
    // само, а удержание — записка для слушателя прокрутки.
    _section.value = index;
    _pinned = index;
  }

  /// Тронули содержимое — подсветка снова следит за прокруткой.
  void _unpin([Object? _]) {
    if (_pinned != null) {
      _pinned = null;
      _followScroll();
    }
  }

  /// Клавиши окна поверх того, что делают сами поля.
  ///
  /// Обработчик стоит **над** содержимым, а не в поле поиска: `PgUp` и `PgDn`
  /// листают, откуда бы их ни нажали — в поле ввода они не значат ничего, а
  /// «полистать читаемое» значат всегда.
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
    if (!_queryFocus.hasFocus || _shown.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _goToSection((_section.value + 1).clamp(0, _shown.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _goToSection((_section.value - 1).clamp(0, _shown.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Страница содержимого.
  ///
  /// Обзором, а не числом строк: разделы разной высоты, и «десять строк» здесь
  /// значило бы разное в каждом. Удержание при этом снимается — подсветка снова
  /// следит за прокруткой: листают тут **читаемое**, а не выбирают раздел.
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

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final padding = dialogContentPadding(context);
    final query = _query.text.trim().toLowerCase();
    _shown = widget.sections(query);

    return Focus(
      // Только слушатель: фокуса не берёт и в обход `Tab` не встаёт — клавиши
      // окна ловятся по дороге наверх от того поля, где фокус сейчас.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder:
            (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _tocWidth(context, theme, constraints.maxWidth, padding.left),
                  child: Padding(
                    padding: EdgeInsets.only(left: padding.left, top: padding.top, bottom: padding.bottom),
                    // Поле поиска стоит **в этом столбце**, а не над обоими: оно
                    // отбирает разделы, и место ему там же, где они. А содержимое
                    // получает всю высоту окна и прокручивается от самого верха.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FcTextField(
                          controller: _query,
                          focusNode: _queryFocus,
                          autofocus: true,
                          hintText: context.strings.tr(widget.searchHint),
                        ),
                        // Счёт — только пока отбирают: «22 settings» при пустом
                        // поле отвечает на вопрос, которого никто не задавал, а
                        // вот «5 settings» объясняет, почему список короткий.
                        if (query.isNotEmpty && widget.countLabel != null)
                          Padding(
                            padding: EdgeInsets.only(top: metrics.dialogLineGap, left: metrics.dialogPadding),
                            child: Text(widget.countLabel!(query), style: _secondaryStyle(theme)),
                          ),
                        SizedBox(height: metrics.dialogGap),
                        // Пустого оглавления не бывает: «ничего не нашлось»
                        // сказано один раз, справа, а пустой список сказал бы то
                        // же самое вторично.
                        if (_shown.isNotEmpty)
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _section,
                              builder:
                                  (context, section, _) => FcPickList(
                                    rows: [for (final shown in _shown) FcPickRow(id: shown.id, title: shown.title)],
                                    // Оглавление отбирают снаружи, а не изнутри:
                                    // раздел, в котором ничего не совпало, из него
                                    // уже пропал, и подсвечивать в оставшихся
                                    // нечего.
                                    query: '',
                                    // Свой отступ: по умолчанию строка списка
                                    // равняется по тексту в поле ввода над ней, а
                                    // здесь поле стоит вплотную.
                                    textInset: metrics.dialogPadding,
                                    selected: section,
                                    // Оглавление не выбирают — оно показывает, где
                                    // вы сейчас, и курсору здесь не обо что
                                    // упереться: ни рамки, ни фона у столбца нет.
                                    mark: FcPickMark.weight,
                                    onTap: (id) => _goToSection(_shown.indexWhere((shown) => shown.id == id)),
                                  ),
                            ),
                          ),
                        // Подвал прижат к низу столбца: место ему там же, где
                        // разделы, но отдельно от них. Ничего не нашлось —
                        // оглавления нет, а подвал остаётся внизу: иначе он
                        // убегал бы под поле поиска на каждый пустой запрос.
                        if (_shown.isEmpty) const Spacer(),
                        if (widget.footer case final footer?) ...[
                          SizedBox(height: metrics.dialogGap),
                          // Слева и по содержимому: столбец растягивает детей, и
                          // кнопка иначе разъехалась бы на всю его ширину.
                          // `scaleDown` — на случай узкого столбца: ширину ему
                          // задают названия разделов, и подпись подвала бывает
                          // длиннее их всех.
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: footer(_refresh)),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child:
                      _shown.isEmpty
                          ? Center(child: Text(context.strings.tr(widget.emptyLabel), style: theme.dialogLabelStyle))
                          // Любое касание содержимого снимает удержание: колесо,
                          // перетаскивание полосы, щелчок по настройке.
                          : Listener(
                            onPointerDown: _unpin,
                            onPointerSignal: _unpin,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              // Поля — **внутри** прокрутки, все четыре: так
                              // содержимое начинается от края окна и уезжает под
                              // заголовок целиком, а не упирается в его тень.
                              padding: padding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (at, shown) in _shown.indexed) ...[
                                    // Просвет **перед** разделом, а не после
                                    // каждого: у первого сверху уже есть поле
                                    // окна. Равен полю окна по бокам.
                                    if (at > 0) SizedBox(height: metrics.dialogHorizontalPadding),
                                    KeyedSubtree(key: _plateOf(shown.id), child: shown.child),
                                  ],
                                ],
                              ),
                            ),
                          ),
                ),
              ],
            ),
      ),
    );
  }

  TextStyle _secondaryStyle(FcTheme theme) =>
      TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, color: theme.colors.dialogLabel);
}
