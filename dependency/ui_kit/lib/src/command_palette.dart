import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_dialog.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

/// Строка палитры: что показать и что запустить.
class PaletteItem {
  const PaletteItem({required this.id, required this.label, required this.owner, required this.keys});

  /// Идентификатор команды — им её и запускают.
  final String id;

  final String label;

  /// Название модуля: «Copy» бывает и у файловых операций, и у просмотрщика.
  final String owner;

  /// Клавиши, за которыми команда закреплена, — уже строками.
  ///
  /// Палитра заодно учит: увидел раз — дальше жмёшь клавишу.
  final String keys;

  FcPickRow get row => FcPickRow(id: id, title: label, subtitle: owner, trailing: keys);
}

/// Палитра команд: список всего, что можно сделать сейчас, с поиском.
///
/// Показывается **только выполнимое**: палитра отвечает на вопрос «что мне
/// доступно», а не «что бывает». Полный перечень остаётся в справке.
///
/// Список и отбор — общие с историей адресов ([FcPickList]); своё здесь одно:
/// `Enter` **запускает** выбранное, а не вписывает его в поле. Поле тут только
/// для поиска.
///
/// Кнопок внизу нет вовсе — ни «Close», ни «Run». Это не окно с формой, которую
/// заполняют и подтверждают, а поиск: набрал, выбрал, нажал `Enter`. Кнопка
/// «Close» повторяла бы `Esc`, а «Run» — `Enter`, и обе отнимали бы у списка
/// строку, ради которой окно и открывают.
class FcCommandPalette extends StatefulWidget {
  const FcCommandPalette({super.key, required this.items, required this.recent, required this.onRun});

  final List<PaletteItem> items;

  /// Недавние — идентификаторами, свежие впереди.
  final List<String> recent;

  /// Запустить выбранное. Окно закрывает вызывающий: у команды может быть своё.
  ///
  /// Закрытие по `Esc` сюда не приходит вовсе — его берёт на себя рама окна
  /// (`onDismiss`), как у всех остальных окон.
  final void Function(String commandId) onRun;

  @override
  State<FcCommandPalette> createState() => _FcCommandPaletteState();
}

class _FcCommandPaletteState extends State<FcCommandPalette> {
  final TextEditingController _query = TextEditingController();

  /// Клавиши списка разбираются на самом поле ввода.
  ///
  /// Стрелки и `Enter` иначе достались бы полю: оно двигает ими курсор и
  /// подтверждает ввод. А обработчик узла срабатывает раньше, чем поле успевает
  /// их истолковать.
  late final FocusNode _field = FocusNode(debugLabel: 'palette', onKeyEvent: _onKey);

  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _selected = 0));
  }

  /// Сколько места отдать списку: целое число строк, а не сколько осталось.
  ///
  /// Окно тянется во всю высоту экрана, и остаток от деления резал бы нижнюю
  /// строку пополам: список выглядел бы обрезанным ровно там, где взгляд ищет
  /// его конец. Поэтому предел округляется **вниз** до целой строки.
  ///
  /// Считается здесь, а не внутри списка: узнать доставшуюся высоту изнутри
  /// можно только `LayoutBuilder`, а он не умеет отвечать на вопрос о
  /// собственной ширине — тот самый, который рама окна задаёт каждому окну
  /// (`IntrinsicWidth`).
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
      FcPickList.filter([for (final item in widget.items) item.row], _query.text, recent: widget.recent);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final found = _found;
    final moved = FcPickList.moveSelection(event, selected: _selected, count: found.length);
    if (moved != null) {
      setState(() => _selected = moved < 0 ? found.length - 1 : moved);
      return KeyEventResult.handled;
    }

    final enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enter && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      if (found.isNotEmpty) {
        widget.onRun(found[_selected.clamp(0, found.length - 1)].id);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final limits = dialogContentLimits(context);
    // Отступ снизу — такой же, каким поле отбито от полосы заголовка: ряда
    // кнопок под списком нет, и без него окно кончалось бы строкой впритык к
    // краю.
    final bottom = metrics.dialogContentTopPadding;

    return ConstrainedBox(
      constraints: limits,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * metrics.dialogWidthFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: dialogContentPadding(context),
              child: FcTextField(controller: _query, focusNode: _field, autofocus: true, hintText: 'Command'),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _listHeight(metrics, limits.maxHeight - bottom)),
              child: FcPickList(rows: _found, query: _query.text, selected: _selected, onTap: widget.onRun),
            ),
            SizedBox(height: bottom),
          ],
        ),
      ),
    );
  }
}
