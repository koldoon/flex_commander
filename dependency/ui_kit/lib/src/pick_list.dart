import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fc_theme.dart';
import 'palette_search.dart';

/// Строка списка с отбором.
///
/// Три части, и все необязательны, кроме первой: имя, приглушённое уточнение
/// рядом с ним и приглушённое же примечание справа. У палитры это команда,
/// модуль и клавиши; у истории адресов — только адрес.
class FcPickRow {
  const FcPickRow({required this.id, required this.title, this.subtitle = '', this.trailing = ''});

  /// Чем строка отзовётся, когда её выберут.
  final String id;

  final String title;

  /// Уточнение сразу за именем: «Copy» бывает у файловых операций и у
  /// просмотрщика.
  final String subtitle;

  /// Справа, приглушённо: клавиши, дата, размер — что угодно, что не спорит с
  /// именем за внимание.
  final String trailing;
}

/// Список с нечётким отбором, подсветкой совпавшего и ходом стрелками.
///
/// Общий у палитры команд и истории адресов: показ строки и отбор у них
/// одинаковые, и держать это в двух местах — верный способ разойтись. А вот
/// смысл `Enter` у них разный (запустить против «вписать в поле»), поэтому
/// нажатие список не толкует: он сообщает о выборе, а решает вызывающий.
class FcPickList extends StatefulWidget {
  const FcPickList({
    super.key,
    required this.rows,
    required this.query,
    required this.selected,
    required this.onTap,
    this.emptyMessage = 'Nothing found',
  });

  final List<FcPickRow> rows;

  /// Набранное: по нему отбирают и подсвечивают.
  final String query;

  /// Который выбран; -1 — не выбран никто.
  final int selected;

  final void Function(String id) onTap;

  final String emptyMessage;

  @override
  State<FcPickList> createState() => _FcPickListState();

  /// Отобранное в том порядке, в каком его покажут.
  ///
  /// Статический, потому что тот же порядок нужен и вызывающему: он держит
  /// выбор номером и должен знать, между чем этот номер ходит.
  static List<FcPickRow> filter(List<FcPickRow> rows, String query, {List<String> recent = const []}) {
    final found = <(FcPickRow, PaletteMatch)>[];
    for (final row in rows) {
      final match = matchCommand(query, label: row.title, owner: row.subtitle);
      if (match != null) {
        found.add((row, match));
      }
    }

    found.sort((a, b) {
      final byMatch = a.$2.compareTo(b.$2);
      if (byMatch != 0 && query.trim().isNotEmpty) {
        return byMatch;
      }
      // Недавнее — последний довод при равном весе, а не самостоятельная сила:
      // искали конкретное, а не привычное.
      final left = recent.indexOf(a.$1.id);
      final right = recent.indexOf(b.$1.id);
      if (left != right) {
        return (left < 0 ? recent.length : left).compareTo(right < 0 ? recent.length : right);
      }
      return byMatch != 0 ? byMatch : a.$1.title.compareTo(b.$1.title);
    });

    return [for (final (row, _) in found) row];
  }

  /// Куда переставить выбор по нажатию; null — клавиша не про список.
  ///
  /// Здесь же и правило края: с первой строки вверх — «никуда» (-1), чтобы
  /// вызывающий мог вернуть набранное руками.
  static int? moveSelection(KeyEvent event, {required int selected, required int count, bool wrap = true}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up || count == 0) {
      return null;
    }

    final next = selected + (down ? 1 : -1);
    if (next >= count) {
      return wrap ? 0 : count - 1;
    }
    if (next < 0) {
      return wrap ? count - 1 : -1;
    }
    return next;
  }
}

class _FcPickListState extends State<FcPickList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FcPickList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      // Выбранное держится на виду: перебор стрелками не должен уезжать за
      // край.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSelected());
    }
  }

  void _showSelected() {
    if (!_scroll.hasClients || widget.selected < 0) {
      return;
    }
    final metrics = FcTheme.of(context).metrics;
    final line = metrics.rowHeight + metrics.rowGap;
    final top = widget.selected * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      _scroll.jumpTo((top + line - position.viewportDimension).clamp(0, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    if (widget.rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: metrics.dialogPadding),
        child: Text(widget.emptyMessage, textAlign: TextAlign.center, style: theme.dialogLabelStyle),
      );
    }

    return SingleChildScrollView(
      // Не ленивый список: рама окна меряет содержимое (`IntrinsicWidth`), а
      // ленивый на такой вопрос отвечать не умеет.
      controller: _scroll,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < widget.rows.length; i++) _row(theme, widget.rows[i], i == widget.selected)],
      ),
    );
  }

  Widget _row(FcTheme theme, FcPickRow row, bool current) {
    final colors = theme.colors;
    final metrics = theme.metrics;
    // Яркое — имя, приглушённое — уточнение и примечание.
    //
    // Роли легко перепутать местами: в теме по умолчанию `dialogLabel` белый, а
    // `dialogText` — приглушённый синий.
    final base = TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize);
    final bright = base.copyWith(color: current ? colors.cursorText : colors.dialogLabel);
    final dim = base.copyWith(color: colors.dialogText);
    final match = matchCommand(widget.query, label: row.title, owner: row.subtitle);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(row.id),
      child: Container(
        height: metrics.rowHeight + metrics.rowGap,
        color: current ? colors.cursorBackground : null,
        padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    ...highlightMatch(row.title, match?.labelHits ?? const [], bright),
                    if (row.subtitle.isNotEmpty) ...[
                      const TextSpan(text: '   '),
                      ...highlightMatch(row.subtitle, match?.ownerHits ?? const [], dim),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (row.trailing.isNotEmpty) ...[
              SizedBox(width: metrics.columnGap),
              Text(row.trailing, style: dim.copyWith(fontFamily: theme.fonts.fixed)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Совпавшие буквы — жирным.
///
/// Без подсветки непонятно, почему строка нашлась: `cpf` в `Copy File` со
/// стороны выглядит случайностью.
List<TextSpan> highlightMatch(String text, List<int> hits, TextStyle style) {
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
