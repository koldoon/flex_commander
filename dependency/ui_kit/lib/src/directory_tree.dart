import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Дерево каталогов в окне: где человек выбирает место, не сходя с него
/// (`docs/spec/settings-presets.md`, §7).
///
/// **Не вид панели.** Дерево панели держит строки ядро: оно помнит раскрытое,
/// глубину и порядок, и живёт это всё в сессии — заводить сессию ради одного
/// окна было бы дорого и видно (лишний набор в ряду). Здесь дерево своё и
/// простое: ветви спрашиваются по одной, у того, кто умеет их перечислять.
///
/// Перечисляет — **панель**: её провайдер знает и `ssh://`, и нутро архива, а
/// дерево знает только адреса, которые он же и вернул.
class FcDirectoryTree extends StatefulWidget {
  const FcDirectoryTree({
    super.key,
    required this.root,
    required this.rootTitle,
    required this.children,
    required this.selected,
    required this.onSelected,
  });

  /// С чего начинается дерево: адрес корня.
  final String root;

  /// Как корень называется в строке: `~` читается хуже, чем «Home».
  final String rootTitle;

  /// Что лежит внутри: каталоги в том порядке, в каком их отдал источник.
  final Future<List<FileEntry>> Function(String path) children;

  /// Что выбрано сейчас — адресом.
  final String selected;

  final void Function(String path) onSelected;

  @override
  State<FcDirectoryTree> createState() => _FcDirectoryTreeState();
}

class _FcDirectoryTreeState extends State<FcDirectoryTree> {
  /// Раскрытые ветви: адрес → что в нём лежит.
  ///
  /// Ветвь, которой здесь нет, закрыта; ветвь с пустым списком раскрыта и
  /// пуста — это разные вещи, и рисуются они по-разному.
  final Map<String, List<FileEntry>> _open = {};

  /// Ветви, ответа по которым ещё ждут: второй раз спрашивать незачем.
  final Set<String> _asked = {};

  final ScrollController _scroll = ScrollController();
  late final FocusNode _keys = FocusNode(debugLabel: 'directory-tree', onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    unawaited(_expand(widget.root));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _keys.dispose();
    super.dispose();
  }

  Future<void> _expand(String path) async {
    if (_open.containsKey(path) || !_asked.add(path)) {
      return;
    }
    final found = await widget.children(path);
    if (!mounted) {
      return;
    }
    setState(() {
      _open[path] = [
        for (final entry in found)
          if (entry.canEnter && entry.kind != EntryKind.parent) entry,
      ];
    });
  }

  void _collapse(String path) {
    setState(() {
      _open.remove(path);
      _asked.remove(path);
    });
  }

  /// Строки дерева сверху вниз: корень и всё, что раскрыто под ним.
  List<_Branch> get _rows {
    final rows = <_Branch>[_Branch(path: widget.root, name: widget.rootTitle, depth: 0)];
    void walk(String path, int depth) {
      for (final entry in _open[path] ?? const <FileEntry>[]) {
        rows.add(_Branch(path: entry.path, name: entry.name, depth: depth));
        walk(entry.path, depth + 1);
      }
    }

    walk(widget.root, 1);
    return rows;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _rows;
    final at = rows.indexWhere((row) => row.path == widget.selected);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _select(rows, at + 1);
      case LogicalKeyboardKey.arrowUp:
        _select(rows, at - 1);
      case LogicalKeyboardKey.arrowRight:
        // Вправо раскрывает, а раскрытую — уводит внутрь: то же, что в панели.
        if (_open.containsKey(widget.selected)) {
          _select(rows, at + 1);
        } else {
          unawaited(_expand(widget.selected));
        }
      case LogicalKeyboardKey.arrowLeft:
        if (_open.containsKey(widget.selected) && widget.selected != widget.root) {
          _collapse(widget.selected);
        } else if (at > 0) {
          // Наверх по дереву, а не по строкам: закрытая ветвь отдаёт ход
          // родителю.
          final depth = rows[at].depth;
          for (var i = at - 1; i >= 0; i--) {
            if (rows[i].depth < depth) {
              _select(rows, i);
              break;
            }
          }
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _select(List<_Branch> rows, int at) {
    if (at < 0 || at >= rows.length) {
      return;
    }
    widget.onSelected(rows[at].path);
    _show(at);
  }

  /// Подтянуть строку в обзор, если её не видно.
  void _show(int at) {
    if (!_scroll.hasClients) {
      return;
    }
    final line = FcTheme.of(context).metrics.rowHeight;
    final top = at * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      position.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      position.jumpTo(top + line - position.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final rows = _rows;

    return Focus(
      focusNode: _keys,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: theme.colors.columnDivider, width: metrics.strokeWidth)),
        child: ListView.builder(
          controller: _scroll,
          itemCount: rows.length,
          itemExtent: metrics.rowHeight,
          itemBuilder: (context, index) => _row(theme, rows[index]),
        ),
      ),
    );
  }

  Widget _row(FcTheme theme, _Branch branch) {
    final metrics = theme.metrics;
    final chosen = branch.path == widget.selected;
    final opened = _open.containsKey(branch.path);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _keys.requestFocus();
        widget.onSelected(branch.path);
        // Один щелчок и выбирает, и раскрывает: закрывать приходится тем же
        // щелчком по уже выбранному — иначе до вложенного каталога не дойти
        // мышью вовсе.
        if (opened && chosen) {
          _collapse(branch.path);
        } else {
          unawaited(_expand(branch.path));
        }
      },
      child: Container(
        height: metrics.rowHeight,
        color: chosen ? theme.colors.cursorBackground : null,
        padding: EdgeInsets.only(left: metrics.dialogPadding + branch.depth * metrics.columnGap * 2),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(
              width: metrics.fontSize,
              child: Icon(
                opened ? theme.icons.caretDown : theme.icons.angleRight,
                size: metrics.fontSize * 0.8,
                color: theme.colors.secondaryText,
              ),
            ),
            SizedBox(width: metrics.columnGap),
            Flexible(
              child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.dialogTextStyle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ветвь на экране: адрес, имя и глубина.
class _Branch {
  const _Branch({required this.path, required this.name, required this.depth});

  final String path;
  final String name;
  final int depth;
}
