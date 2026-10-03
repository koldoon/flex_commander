import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_dialog.dart';
import 'app_scope.dart';
import 'fc_theme.dart';
import 'palette_search.dart';
import 'pick_list.dart';

/// Строка палитры: что показать и что запустить.
class PaletteItem {
  const PaletteItem({
    required this.id,
    required this.label,
    required this.owner,
    required this.keys,
    this.description = '',
    this.keywords = const [],
  });

  /// Идентификатор команды — им её и запускают.
  final String id;

  final String label;

  /// Что команда делает — одним коротким предложением, рядом с названием.
  ///
  /// Ровно тот вопрос, ради которого в палитру заходят с полузнакомой командой.
  /// Пустое — пустое место: у «Cursor up» объяснять нечего, и подставлять туда
  /// модуль ради заполненной колонки нельзя.
  final String description;

  /// Название модуля: «Copy» бывает и у файловых операций, и у просмотрщика.
  ///
  /// В строке его не видно — там стоит [description], — но искать по нему
  /// по-прежнему можно: `term` находит команды терминала. Поэтому модуль и
  /// уходит к синонимам, в невидимые признаки.
  final String owner;

  /// Клавиши, за которыми команда закреплена, — уже строками.
  ///
  /// Палитра заодно учит: увидел раз — дальше жмёшь клавишу.
  final String keys;

  /// Слова, по которым команда находится, хотя в названии их нет: `gz` у
  /// «Mk Tar». В строке они не показываются — искать по ним можно, читать
  /// нечего.
  final List<String> keywords;

  FcPickRow get row => FcPickRow(
    id: id,
    title: label,
    subtitle: description,
    trailing: keys,
    keywords: [...keywords, if (owner.isNotEmpty) owner],
  );
}

/// Палитра команд: список всего, что можно сделать сейчас, с поиском.
///
/// Показывается **только выполнимое**: палитра отвечает на вопрос «что мне
/// доступно», а не «что бывает». Полный перечень остаётся в справке.
///
/// Окно — общее [FcPickPalette]; своё здесь одно: `Enter` **запускает**
/// выбранное.
class FcCommandPalette extends StatelessWidget {
  const FcCommandPalette({super.key, required this.items, required this.recent, required this.onRun});

  final List<PaletteItem> items;

  /// Недавние — идентификаторами, свежие впереди.
  final List<String> recent;

  /// Запустить выбранное. Окно закрывает вызывающий: у команды может быть своё.
  final void Function(String commandId) onRun;

  @override
  Widget build(BuildContext context) => FcPickPalette(
    rows: [for (final item in items) item.row],
    recent: recent,
    hint: context.strings.tr('Command'),
    onPick: onRun,
  );
}

/// Окно-палитра: поле отбора сверху, список под ним, `Enter` выбирает.
///
/// Его разделяют палитра команд и оглавление PDF (`docs/spec/pdf-viewer.md`,
/// §16.1): раскладка, клавиши и высота у них одни, разное — что в списке и в
/// каком порядке.
///
/// Список и отбор — общие с историей адресов ([FcPickList]). Поле тут только
/// для поиска.
///
/// Кнопок внизу нет вовсе — ни «Close», ни «Run». Это не окно с формой, которую
/// заполняют и подтверждают, а поиск: набрал, выбрал, нажал `Enter`. Кнопка
/// «Close» повторяла бы `Esc`, а «Run» — `Enter`, и обе отнимали бы у списка
/// строку, ради которой окно и открывают.
class FcPickPalette extends StatefulWidget {
  const FcPickPalette({
    super.key,
    required this.rows,
    required this.hint,
    required this.onPick,
    this.recent = const [],
    this.keepOrder = false,
    this.initial,
  });

  final List<FcPickRow> rows;

  /// Подсказка в пустом поле — она же имя окна: полосы заголовка нет.
  final String hint;

  /// Недавние — идентификаторами, свежие впереди.
  final List<String> recent;

  /// Держать порядок строк, а не сортировать по весу совпадения: у оглавления
  /// порядок — это порядок документа, и отбор только прячет неподходящее.
  final bool keepOrder;

  /// На какой строке стоять, пока ничего не набрано; null — на первой.
  final String? initial;

  /// Выбрали строку. Окно закрывает вызывающий.
  ///
  /// Закрытие по `Esc` сюда не приходит вовсе — его берёт на себя рама окна
  /// (`onDismiss`), как у всех остальных окон.
  final void Function(String id) onPick;

  @override
  State<FcPickPalette> createState() => _FcPickPaletteState();
}

class _FcPickPaletteState extends State<FcPickPalette> {
  final TextEditingController _query = TextEditingController();

  /// Клавиши списка разбираются на самом поле ввода.
  ///
  /// Стрелки и `Enter` иначе достались бы полю: оно двигает ими курсор и
  /// подтверждает ввод. А обработчик узла срабатывает раньше, чем поле успевает
  /// их истолковать.
  late final FocusNode _field = FocusNode(debugLabel: 'palette', onKeyEvent: _onKey);

  final FcPickPage _page = FcPickPage();

  late int _selected = _initialIndex();

  int _initialIndex() {
    final index = widget.initial == null ? -1 : widget.rows.indexWhere((row) => row.id == widget.initial);
    return index < 0 ? 0 : index;
  }

  /// Набранное в прошлый раз. Поле зовёт слушателя и на смену выделения —
  /// получив фокус, например, — а сбрасывать курсор на первую строку надо
  /// только тогда, когда отбор и правда поменялся. Иначе оглавление,
  /// открытое на текущем разделе, тут же перескакивало бы к первому.
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      if (_query.text == _lastQuery) {
        return;
      }
      _lastQuery = _query.text;
      setState(() => _selected = 0);
    });
  }

  double _listHeight(FcMetrics metrics, double available) {
    final line = metrics.rowHeight + metrics.rowGap;
    // Своё место занимают поле ввода и его отступы — всё, что стоит над
    // списком.
    final free = available - (metrics.dialogContentTopPadding + metrics.inputHeight + metrics.dialogPadding);
    final rows = (free / line).floor();

    // На совсем тесном экране целой строки не помещается вовсе: тогда лучше
    // показать половину, чем ничего.
    return rows < 1 ? free.clamp(0, double.infinity) : rows * line;
  }

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  List<FcPickRow> get _found =>
      widget.keepOrder
          ? [
            for (final row in widget.rows)
              if (matchCommand(_query.text, label: row.title, keywords: row.keywords) != null) row,
          ]
          : FcPickList.filter(widget.rows, _query.text, recent: widget.recent);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final found = _found;
    final moved = FcPickList.moveSelection(event, selected: _selected, count: found.length, page: _page);
    if (moved != null) {
      setState(() => _selected = moved < 0 ? found.length - 1 : moved);
      return KeyEventResult.handled;
    }

    final enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enter && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      if (found.isNotEmpty) {
        widget.onPick(found[_selected.clamp(0, found.length - 1)].id);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    // Полосы заголовка у палитры нет, и высоту она не отнимает: окно называет
    // себя первой же строкой — полем ввода с подсказкой. А сверху у неё не
    // поле, а место (`dialogTopInset`): палитра стоит под верхним краем и с
    // него не сходит, поэтому и высота меряется от него.
    final limits = dialogContentLimits(context, titled: false, topInset: metrics.dialogTopInset);
    // Отступ снизу — такой же, как сверху: ряда кнопок под списком нет, и без
    // него окно кончалось бы строкой впритык к краю.
    final bottom = metrics.dialogContentTopPadding;

    return ConstrainedBox(
      constraints: limits,
      child: SizedBox(
        // Своя доля, шире прочих окон: палитра это список, и в строке у неё
        // название, описание и клавиши разом.
        width: MediaQuery.sizeOf(context).width * metrics.paletteWidthFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: dialogContentPadding(context),
              child: FcTextField(controller: _query, focusNode: _field, autofocus: true, hintText: widget.hint),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _listHeight(metrics, limits.maxHeight - bottom)),
              child: FcPickList(
                rows: _found,
                query: _query.text,
                selected: _selected,
                page: _page,
                onTap: widget.onPick,
              ),
            ),
            SizedBox(height: bottom),
          ],
        ),
      ),
    );
  }
}
