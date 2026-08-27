import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_dialog.dart';
import 'fc_theme.dart';
import 'palette_search.dart';

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
}

/// Палитра команд: список всего, что можно сделать сейчас, с поиском.
///
/// Показывается **только выполнимое**: палитра отвечает на вопрос «что мне
/// доступно», а не «что бывает». Полный перечень остаётся в справке.
class FcCommandPalette extends StatefulWidget {
  const FcCommandPalette({
    super.key,
    required this.items,
    required this.recent,
    required this.onRun,
    required this.onClose,
  });

  final List<PaletteItem> items;

  /// Недавние — идентификаторами, свежие впереди.
  final List<String> recent;

  /// Запустить выбранное. Окно закрывает вызывающий: у команды может быть своё.
  final void Function(String commandId) onRun;

  final VoidCallback onClose;

  @override
  State<FcCommandPalette> createState() => _FcCommandPaletteState();
}

class _FcCommandPaletteState extends State<FcCommandPalette> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

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

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _field.dispose();
    super.dispose();
  }

  /// Отобранное и упорядоченное.
  ///
  /// При пустом запросе впереди идут недавние, а следом — всё остальное:
  /// обычно человек открывает палитру ради того же, что делал вчера, но она
  /// остаётся и каталогом.
  List<(PaletteItem, PaletteMatch)> get _found {
    final query = _query.text;
    final found = <(PaletteItem, PaletteMatch)>[];
    for (final item in widget.items) {
      final match = matchCommand(query, label: item.label, owner: item.owner);
      if (match != null) {
        found.add((item, match));
      }
    }

    found.sort((a, b) {
      final byMatch = a.$2.compareTo(b.$2);
      if (byMatch != 0 && query.trim().isNotEmpty) {
        return byMatch;
      }
      // Недавность — последний довод при равном весе, а не самостоятельная
      // сила: искали конкретное, а не привычное.
      final left = widget.recent.indexOf(a.$1.id);
      final right = widget.recent.indexOf(b.$1.id);
      if (left != right) {
        return (left < 0 ? widget.recent.length : left).compareTo(right < 0 ? widget.recent.length : right);
      }
      return byMatch != 0 ? byMatch : a.$1.label.compareTo(b.$1.label);
    });

    return found;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final count = _found.length;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1, count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1, count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _run();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta, int count) {
    if (count == 0) {
      return;
    }
    setState(() => _selected = (_selected + delta) % count);
    if (_selected < 0) {
      setState(() => _selected += count);
    }
    _showSelected();
  }

  /// Выбранное держится на виду: перебор стрелками не должен уезжать за край.
  void _showSelected() {
    if (!_scroll.hasClients) {
      return;
    }
    final metrics = FcTheme.of(context).metrics;
    final line = metrics.rowHeight + metrics.rowGap;
    final top = _selected * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + line - position.viewportDimension);
    }
  }

  void _run() {
    final found = _found;
    if (found.isEmpty) {
      return;
    }
    widget.onRun(found[_selected.clamp(0, found.length - 1)].$1.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final found = _found;

    return ConstrainedBox(
      constraints: dialogContentLimits(context),
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
            Flexible(
              child:
                  found.isEmpty
                      ? Padding(
                        padding: EdgeInsets.only(bottom: metrics.dialogPadding),
                        child: Text('Nothing found', textAlign: TextAlign.center, style: theme.dialogLabelStyle),
                      )
                      // Не ленивый список: рама окна меряет содержимое
                      // (`IntrinsicWidth`), а ленивый на такой вопрос отвечать
                      // не умеет — да и команд полсотни, лень тут не нужна.
                      : SingleChildScrollView(
                        controller: _scroll,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [for (var i = 0; i < found.length; i++) _row(theme, found[i], i == _selected)],
                        ),
                      ),
            ),
            CommandDialogActions(actions: [FcButton(label: 'Close', onPressed: widget.onClose)]),
          ],
        ),
      ),
    );
  }

  Widget _row(FcTheme theme, (PaletteItem, PaletteMatch) found, bool selected) {
    final (item, match) = found;
    final colors = theme.colors;
    final metrics = theme.metrics;
    final base = TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize, color: colors.dialogText);
    final dim = base.copyWith(color: colors.dialogLabel);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onRun(item.id),
      child: Container(
        height: metrics.rowHeight + metrics.rowGap,
        color: selected ? colors.cursorBackground : null,
        padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    ..._highlight(
                      item.label,
                      match.labelHits,
                      selected ? base.copyWith(color: colors.cursorText) : base,
                    ),
                    // Модуль — сразу за названием и приглушённо: он уточняет,
                    // чей это «Copy», а не спорит с ним за внимание.
                    const TextSpan(text: '   '),
                    ..._highlight(item.owner, match.ownerHits, dim),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.keys.isNotEmpty) ...[
              SizedBox(width: metrics.columnGap),
              Text(item.keys, style: dim.copyWith(fontFamily: theme.fonts.fixed)),
            ],
          ],
        ),
      ),
    );
  }

  /// Совпавшие буквы — жирным.
  ///
  /// Без этого непонятно, почему строка нашлась: `cpf` в `Copy File` со стороны
  /// выглядит случайностью.
  List<TextSpan> _highlight(String text, List<int> hits, TextStyle style) {
    if (hits.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final spans = <TextSpan>[];
    final marked = hits.toSet();
    final buffer = StringBuffer();
    var bold = marked.contains(0);

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString(), style: bold ? style.copyWith(fontWeight: FontWeight.bold) : style));
        buffer.clear();
      }
    }

    for (var i = 0; i < text.length; i++) {
      final now = marked.contains(i);
      if (now != bold) {
        flush();
        bold = now;
      }
      buffer.write(text[i]);
    }
    flush();

    return spans;
  }
}
