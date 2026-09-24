import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'color_field.dart';
import 'command_dialog.dart';
import 'dialog_body.dart';
import 'controls.dart';
import 'fc_theme.dart';
import 'indexed_sections.dart';
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

  /// Что набрано в поиске **сейчас**: поле ввода принадлежит общему виджету
  /// разделов, а подсветка найденного в блоках — этому окну.
  String _query = '';

  /// Сколько настроек осталось после отбора — считается по показанным
  /// разделам, а не по всем.
  int _count = 0;

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
    setState(() {});
  }

  @override
  void dispose() {
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
  List<FcIndexedSection> _sectionsFor(String query) {
    _query = query;
    final found = [
      for (final (title, schema) in _pages)
        if (query.isEmpty || title.toLowerCase().contains(query))
          (title, schema, schema.fields)
        else if (schema.fields.where((field) => _matches(field, query)).toList() case final fields
            when fields.isNotEmpty)
          (title, schema, fields),
    ];
    _count = found.fold(0, (sum, section) => sum + section.$3.length);

    return [
      for (final (title, schema, fields) in found)
        FcIndexedSection(title: title, child: _page(FcTheme.of(context), title, schema, fields)),
    ];
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
    if (_query.isEmpty) {
      return const [];
    }
    final at = text.toLowerCase().indexOf(_query);
    return at < 0 ? const [] : [for (var i = 0; i < _query.length; i++) at + i];
  }

  /// Раздел целиком — плашка с заголовком и блоками настроек.
  Widget _page(FcTheme theme, String title, SettingsSchema schema, List<SettingsField> fields) {
    final metrics = theme.metrics;
    return FcPlate(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(theme, title),
          for (final (at, field) in fields.indexed) ...[
            // Линейка **между** настройками, а не под каждой: края раздела
            // рисует плашка вокруг него, и линейка по её кромке была бы второй
            // границей на том же месте. То же правило у таблицы справки, и
            // линейка та же — иначе соседние настройки читаются одним сплошным
            // столбцом.
            if (at > 0) ...[
              SizedBox(height: metrics.sectionEntryGap),
              Container(height: metrics.strokeWidth, color: theme.colors.columnDivider),
            ],
            // Над подписью просвет **меньше** на пустоту, которую строка текста
            // несёт над буквами: равные числа дают неравные просветы, и
            // настройка стояла бы ближе к своей линейке снизу, чем к чужой
            // сверху (`docs/spec/settings-editor.md`, §12).
            SizedBox(height: metrics.sectionEntryGap - metrics.fontCapInset),
            // Ключом по полю: отбор и пересборка не должны менять настройке её
            // состояние.
            _Block(key: ValueKey(field.id), form: this, schema: schema, field: field),
          ],
          // До кромки плашки — столько же, сколько до линейки: своего поля у
          // плашки меньше, и последняя настройка липла к её нижнему краю.
          SizedBox(height: metrics.sectionEntryGap - metrics.dialogPadding),
        ],
      ),
    );
  }

  TextEditingController _editorFor(String id, String initial) =>
      _editors.putIfAbsent(id, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return SizedBox(
      // Своя доля, шире прочих окон: колонок здесь две, и обе с текстом.
      width: MediaQuery.sizeOf(context).width * metrics.settingsWidthFactor,
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
          // Оглавление, поиск и прокрутка к разделу — общие: тем же виджетом
          // устроена справка (`docs/spec/help-window.md`, §2).
          child: FcIndexedSections(
            sections: _sectionsFor,
            titles: [for (final (title, _) in _pages) title],
            searchHint: widget.searchHint,
            countLabel: (_) => _countLabel,
            footer: widget.footer == null ? null : (refresh) => widget.footer!(_rebuild),
          ),
        ),
      ),
    );
  }

  /// Сколько настроек осталось после отбора.
  String get _countLabel {
    final count = _count;
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
  Widget _heading(FcTheme theme, String title) => Padding(
    // По той же левой границе, что и настройки: под ними стоит место под
    // полосу пометки, и без отступа заголовок висел бы левее столбца.
    padding: EdgeInsets.only(left: theme.metrics.markedBarWidth + theme.metrics.columnGap),
    child: Text(
      title,
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
  ///
  /// [redraw] перерисовывает **эту настройку**, а не форму: правка меняет её
  /// значение и её же пометку, а соседям до неё дела нет. Через `setState`
  /// формы одно нажатие клавиши пересобирало все поля разом — в окне настроек
  /// это тысяча виджетов, в редакторе тем восемнадцать
  /// (`docs/spec/settings-editor.md`, §14).
  Widget _block(FcTheme theme, SettingsSchema schema, SettingsField field, VoidCallback redraw) {
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
                  _titleLine(theme, schema, field, Text.rich(_titleSpan(theme, field.title)), redraw),
                  for (final line in explanations) ...[SizedBox(height: metrics.dialogLineGap), line],
                ],
              ),
            ),
            SizedBox(width: metrics.columnGap),
            _control(theme, schema, field, redraw),
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
            _titleLine(theme, schema, field, _control(theme, schema, field, redraw), redraw),
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
            // Кнопка-приставка — **отдельной строкой под настройкой**, с
            // полем в обычный междустрочный промежуток и **без отступа
            // слева**.
            //
            // Ни то ни другое не косметика. Отступ равнял бы кнопку по
            // подписи флажка — то есть говорил бы, что она к флажку
            // относится; а она живёт сама по себе: отказ делать по расписанию
            // не значит отказа сделать сейчас, и нажимают её при любом
            // положении галочки. Промежуток — тот же, каким отделены друг от
            // друга соседние настройки: кнопка им и приходится соседкой, а не
            // продолжением подсказки (`docs/spec/self-update.md`, §8).
            if (field.action case final action?)
              Padding(
                padding: EdgeInsets.only(top: metrics.dialogGap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [_actionButton(action)]),
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
          _titleLine(theme, schema, field, Text.rich(_titleSpan(theme, field.title)), redraw),
          for (final line in explanations) ...[SizedBox(height: metrics.dialogLineGap), line],
          SizedBox(height: metrics.dialogLineGap),
          _control(theme, schema, field, redraw),
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
  Widget _titleLine(FcTheme theme, SettingsSchema schema, SettingsField field, Widget title, VoidCallback redraw) {
    if (field.isDefault) {
      return title;
    }
    return Row(
      children: [
        Flexible(child: title),
        SizedBox(width: theme.metrics.columnGap),
        _reset(theme, schema, field, redraw),
      ],
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

  Widget _reset(FcTheme theme, SettingsSchema schema, SettingsField field, VoidCallback redraw) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () {
        field.resetToDefault();
        _refreshEditor(field);
        schema.save();
        redraw();
      },
      child: Text(context.strings.tr('Reset'), style: _secondaryStyle(theme).copyWith(color: theme.colors.markedBar)),
    ),
  );

  /// Флажок — сам по себе; кнопка-приставка стоит **под** ним, отдельной
  /// строкой (см. [_block]).
  Widget _flagControl(FcTheme theme, SettingsFlag flag, VoidCallback changed) {
    return FcCheckbox(
      label: flag.title,
      richLabel: _titleSpan(theme, flag.title),
      value: flag.read(),
      onChanged: (value) {
        flag.write(value);
        changed();
      },
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

  Widget _control(FcTheme theme, SettingsSchema schema, SettingsField field, VoidCallback redraw) {
    void changed() {
      schema.save();
      redraw();
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
      SettingsOption option => Wrap(
        // Одной строкой со списком: кнопки — про то, что в нём выбрано, и
        // отдельной строкой читались бы как своё, отдельное дело. `Wrap` —
        // чтобы в узком окне ряд переносился, а не лез за край.
        spacing: theme.metrics.dialogGap,
        runSpacing: theme.metrics.dialogLineGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FcSelect<String>(
            options: option.allowed,
            value: option.read(),
            onChanged: (value) {
              option.write(value);
              switched();
            },
          ),
          for (final action in option.actions) _actionButton(action),
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

/// Одна настройка — своим виджетом.
///
/// Затем, что правка перерисовывает **её**: значение и пометка «тронуто» — её
/// собственные, а соседям до них дела нет. Пока блок рисовался прямо в форме,
/// одно нажатие клавиши пересобирало все поля разом
/// (`docs/spec/settings-editor.md`, §14).
///
/// Форму блок держит **ссылкой на состояние**: поля ввода, строки списков и
/// подсветка найденного живут там — они переживают и отбор, и пересборку, а в
/// блоке жили бы ровно до первой.
class _Block extends StatefulWidget {
  const _Block({super.key, required this.form, required this.schema, required this.field});

  final _FcSettingsFormState form;
  final SettingsSchema schema;
  final SettingsField field;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  @override
  Widget build(BuildContext context) => widget.form._block(FcTheme.of(context), widget.schema, widget.field, () {
    if (mounted) {
      setState(() {});
    }
  });
}
