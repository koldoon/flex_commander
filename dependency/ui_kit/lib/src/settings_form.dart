import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'command_dialog.dart';
import 'controls.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

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
class FcSettingsForm extends StatefulWidget {
  const FcSettingsForm({super.key, required this.pages, required this.onClose});

  final List<SettingsPage> pages;

  /// Закрыть — единственное действие окна.
  final VoidCallback onClose;

  @override
  State<FcSettingsForm> createState() => _FcSettingsFormState();
}

class _FcSettingsFormState extends State<FcSettingsForm> {
  /// Насколько плавно оглавление уводит к разделу.
  ///
  /// Прыжком нельзя: человек щёлкнул по названию, а не «перенеси меня» — по
  /// движению видно, что список тот же самый и куда он уехал.
  static const Duration _scrollTo = Duration(milliseconds: 120);

  /// Схемы строятся один раз на открытие: они держат замыкания к разделам, и
  /// пересобирать их на каждый кадр незачем.
  late final List<(String, SettingsSchema)> _pages = [for (final page in widget.pages) (page.title, page.build())];

  /// Заголовки разделов — по ключу на каждый: по ним считается, где раздел
  /// начинается, и для оглавления, и для прокрутки к нему.
  late final List<GlobalKey> _headings = [for (final _ in _pages) GlobalKey()];

  /// Поля ввода живут столько же, сколько окно: контроллер помнит набранное и
  /// положение курсора, а пересозданный терял бы и то и другое.
  final Map<String, TextEditingController> _editors = {};

  final ScrollController _scroll = ScrollController();

  /// Набранное в поиске.
  final TextEditingController _query = TextEditingController();

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

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    for (final editor in _editors.values) {
      editor.dispose();
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
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  static bool _matches(SettingsField field, String query) =>
      field.title.toLowerCase().contains(query) ||
      field.description.toLowerCase().contains(query) ||
      field.id.toLowerCase().contains(query);

  /// Где в строке стоит найденное — чтобы его выделить.
  List<int> _hits(String text) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) {
      return const [];
    }
    final at = text.toLowerCase().indexOf(query);
    return at < 0 ? const [] : [for (var i = 0; i < query.length; i++) at + i];
  }

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

  TextEditingController _editorFor(String id, String initial) =>
      _editors.putIfAbsent(id, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    final padding = dialogContentPadding(context);

    return SizedBox(
      // Своя доля, шире прочих окон: колонок здесь две, и обе с текстом.
      width: MediaQuery.sizeOf(context).width * metrics.settingsWidthFactor,
      child: ConstrainedBox(
        // Предел по высоте — то же правило, что у справки: без него прокрутка
        // не работает, `Flexible` получает бесконечность, и форма вылезает за
        // экран.
        constraints: dialogContentLimits(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(left: padding.left, right: padding.right, top: padding.top),
              child: Row(
                children: [
                  Expanded(child: FcTextField(controller: _query, autofocus: true, hintText: 'Search settings')),
                  // Счёт — только пока отбирают: «22 settings» при пустом поле
                  // отвечает на вопрос, которого никто не задавал, а вот
                  // «5 settings» объясняет, почему список вдруг короткий.
                  if (_query.text.trim().isNotEmpty) ...[
                    SizedBox(width: metrics.columnGap),
                    Text(_countLabel, style: _secondaryStyle(theme)),
                  ],
                ],
              ),
            ),
            Flexible(
              // Растяжкой, а не по содержимому: обе колонки прокручиваются
              // сами, и высоту им должен задать ряд, иначе мерить её будет
              // нечем.
              child:
                  _found.isEmpty
                      // Одним сообщением на оба столбца: пустое оглавление
                      // рядом с пустым списком сказало бы то же самое дважды.
                      ? Center(child: Text('Nothing found', style: theme.dialogLabelStyle))
                      : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: metrics.settingsTocWidth,
                            child: Padding(
                              padding: EdgeInsets.only(left: padding.left, top: padding.top, bottom: padding.bottom),
                              child: FcPickList(
                                rows: [for (final (_, title, _, _) in _found) FcPickRow(id: title, title: title)],
                                // Оглавление отбирают снаружи, а не изнутри:
                                // раздел, в котором ничего не совпало, из него
                                // уже пропал, и подсвечивать в оставшихся
                                // нечего.
                                query: '',
                                // Свой отступ: по умолчанию строка списка
                                // равняется по тексту в поле ввода над ней, а
                                // над оглавлением поля нет — есть край окна.
                                textInset: metrics.dialogPadding,
                                selected: _section,
                                // Оглавление не выбирают — оно показывает, где
                                // вы сейчас, и курсору здесь не обо что
                                // упереться: ни рамки, ни фона у столбца нет.
                                mark: FcPickMark.weight,
                                onTap: (id) => _goToSection(_found.indexWhere((section) => section.$2 == id)),
                              ),
                            ),
                          ),
                          Expanded(
                            // Отступ от поля поиска — **снаружи** прокрутки, как
                            // у оглавления: внутри он уезжал бы вместе с
                            // содержимым, и настройки подлезали бы под поле.
                            child: Padding(
                              padding: EdgeInsets.only(top: padding.top),
                              // Любое касание списка снимает удержание: колесо,
                              // перетаскивание полосы, щелчок по настройке.
                              child: Listener(
                                onPointerDown: _unpin,
                                onPointerSignal: _unpin,
                                child: SingleChildScrollView(
                                  controller: _scroll,
                                  // Те же поля, что и у справки: окна не должны
                                  // быть отбиты по-разному.
                                  padding: EdgeInsets.only(
                                    left: padding.left,
                                    right: padding.right,
                                    bottom: padding.bottom,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (final (position, (index, title, schema, fields)) in _found.indexed) ...[
                                        // Просвет **перед** заголовком, а не
                                        // после каждого раздела: у первого
                                        // сверху уже есть поле окна.
                                        if (position > 0) SizedBox(height: metrics.sectionGap),
                                        _heading(theme, title, key: _headings[index]),
                                        for (final field in fields) ...[
                                          SizedBox(height: metrics.sectionEntryGap),
                                          _block(theme, schema, field),
                                        ],
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
            SizedBox(height: metrics.dialogGap),
            CommandDialogActions(actions: [FcButton(label: 'Close', onPressed: widget.onClose)]),
          ],
        ),
      ),
    );
  }

  /// Сколько настроек осталось после отбора.
  String get _countLabel {
    final count = _found.fold(0, (sum, section) => sum + section.$4.length);
    return count == 1 ? '1 setting' : '$count settings';
  }

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
    final editor = _editors[field.id];
    if (editor == null) {
      return;
    }
    final value = switch (field) {
      SettingsNumber number => '${number.read()}',
      SettingsText text => text.read(),
      _ => null,
    };
    if (value != null) {
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
      child: Text('Reset', style: _secondaryStyle(theme).copyWith(color: theme.colors.markedBar)),
    ),
  );

  Widget _control(FcTheme theme, SettingsSchema schema, SettingsField field) {
    void changed() {
      schema.save();
      setState(() {});
    }

    return switch (field) {
      SettingsFlag flag => FcCheckbox(
        label: flag.title,
        richLabel: _titleSpan(theme, flag.title),
        value: flag.read(),
        onChanged: (value) {
          flag.write(value);
          changed();
        },
      ),
      // Выпадающим списком, а не переключателем: темы приносят модули, и
      // строка на каждый вариант росла бы вместе с их числом.
      SettingsChoice choice => FcSelect<String>(
        options: choice.options,
        value: choice.read(),
        onChanged: (value) {
          choice.write(value);
          changed();
        },
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
