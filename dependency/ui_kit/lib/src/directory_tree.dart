import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chain_name.dart';
import 'fc_theme.dart';
import 'plate.dart';

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
    this.shows,
    this.compact = false,
  });

  /// Склеивать цепочки: каталог, в котором ровно один каталог, стоит одной
  /// строкой с ним — `src/main/java/com/acme`
  /// (`docs/spec/panel-view-compact-tree.md`, §13). Выключен — дерево ровно
  /// прежнее.
  final bool compact;

  /// С чего начинается дерево: адрес корня.
  ///
  /// Бывает сокращением — `~`: его разбирает источник, а не экран. Настоящий
  /// путь дерево узнаёт от первой же ветви и тогда сообщает его наружу: в
  /// строке выбора человек должен видеть место, а не сокращение.
  final String root;

  /// Как корень называется в строке: `~` читается хуже, чем «Home».
  final String rootTitle;

  /// Что лежит внутри: каталоги в том порядке, в каком их отдал источник.
  final Future<List<FileEntry>> Function(String path) children;

  /// Что выбрано сейчас — адресом.
  final String selected;

  /// Выбрали строку: адрес и то, файл это или ветвь.
  ///
  /// Файл или ветвь — врозь, потому что спросившему это разное: окно загрузки
  /// от файла берёт имя, а от ветви — только место
  /// (`docs/spec/settings-presets.md`, §7).
  final void Function(String path, bool isFile) onSelected;

  /// Какие файлы показывать рядом с ветвями; null — только ветви.
  ///
  /// Окну загрузки файл нужен целиком: набирать его имя руками, когда он виден
  /// в том же дереве, незачем.
  final bool Function(FileEntry entry)? shows;

  @override
  State<FcDirectoryTree> createState() => _FcDirectoryTreeState();
}

class _FcDirectoryTreeState extends State<FcDirectoryTree> {
  /// Раскрытые ветви: адрес → что в нём лежит.
  ///
  /// Ветвь, которой здесь нет, закрыта; ветвь с пустым списком раскрыта и
  /// пуста — это разные вещи, и рисуются они по-разному.
  final Map<String, List<FileEntry>> _open = {};

  /// Адрес корня — настоящий, если его уже удалось узнать.
  late String _root = widget.root;

  /// Ветви, ответа по которым ещё ждут: второй раз спрашивать незачем.
  final Set<String> _asked = {};

  final ScrollController _scroll = ScrollController();
  late final FocusNode _keys = FocusNode(debugLabel: 'directory-tree', onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    unawaited(_expand(_root));
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
    final children = [
      for (final entry in found)
        if (entry.kind != EntryKind.parent && (entry.canEnter || (widget.shows?.call(entry) ?? false))) entry,
    ];

    // Настоящий путь корня — от первой же ветви: она знает, в каком каталоге
    // лежит. Спросить его больше не у кого: дом разбирает источник.
    final real = path == _root && _root == widget.root ? children.firstOrNull?.directoryPath ?? '' : '';
    setState(() {
      if (real.isNotEmpty) {
        final chosenRoot = widget.selected == _root;
        _open[real] = children;
        _open.remove(_root);
        _root = real;
        if (chosenRoot) {
          // Корень — ветвь, а не файл: настоящий адрес дома узнали и сказали.
          _choose(real, false);
        }
      } else {
        _open[path] = children;
      }
    });

    if (!widget.compact) {
      return;
    }
    // Выбранное могло уйти в цепочку — тогда оно переезжает на её строку:
    // выделенной должна быть та строка, чьё место стоит в окне (§13).
    _followChain();
    // Свежее раскрытие идёт по цепочке дальше: внутри один каталог — он
    // раскрывается тоже, до развилки. Корень не склеивается, и за него не
    // идём. Прочитанное **сейчас**: свёрнутое человеком само не раскроется —
    // сюда оно не попадает.
    if (path != _root && real.isEmpty && children.length == 1 && children.single.kind == EntryKind.directory) {
      unawaited(_expand(children.single.path));
    }
  }

  /// Выбранный адрес, поглощённый цепочкой, — на её строку.
  void _followChain() {
    final row = _shownAs[_chosen];
    if (row != null) {
      _choose(row, false);
    }
  }

  /// Последний выбор — свой, а не из параметра.
  ///
  /// Выбор уходит наверх, а возвращается параметром только со следующим
  /// кадром; ветвь же прочитаться успевает раньше. Сверяйся склейка с
  /// параметром — она видела бы прежний выбор, и выбранный каталог, ушедший в
  /// цепочку, так и остался бы без строки (§13).
  late String _chosen = widget.selected;

  void _choose(String path, bool isFile) {
    _chosen = path;
    widget.onSelected(path, isFile);
  }

  @override
  void didUpdateWidget(FcDirectoryTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _chosen = widget.selected;
    }
  }

  void _collapse(String path) {
    setState(() {
      _open.remove(path);
      _asked.remove(path);
    });
  }

  /// Строки дерева сверху вниз: корень и всё, что раскрыто под ним.
  List<_Branch> get _rows => _layout().$1;

  /// Поглощённый цепочкой адрес → адрес строки, которой он показан.
  Map<String, String> get _shownAs => _layout().$2;

  (List<_Branch>, Map<String, String>) _layout() {
    final rows = <_Branch>[_Branch(path: _root, name: widget.rootTitle, depth: 0)];
    final shownAs = <String, String>{};
    void walk(String path, int depth) {
      for (final top in _open[path] ?? const <FileEntry>[]) {
        var entry = top;
        final head = <String>[];
        // Цепочка (§13): раскрытый прочитанный каталог с единственным каталогом
        // внутри поглощается им. Ссылка и файл цепочку обрывают, закрытый
        // каталог её завершает.
        if (widget.compact) {
          while (entry.kind == EntryKind.directory) {
            final inside = _open[entry.path];
            if (inside == null || inside.length != 1 || inside.single.kind != EntryKind.directory) {
              break;
            }
            head.add(entry.name);
            shownAs[entry.path] = inside.single.path;
            entry = inside.single;
          }
        }
        rows.add(
          _Branch(path: entry.path, name: entry.name, head: head.join('/'), depth: depth, leaf: !entry.canEnter),
        );
        walk(entry.path, depth + 1);
      }
    }

    walk(_root, 1);
    // Цепочка из трёх и больше звеньев сказала о каждом поглощённом лишь
    // следующее звено — доводим до строки, которой он показан.
    for (final key in shownAs.keys.toList()) {
      var at = shownAs[key]!;
      for (var next = shownAs[at]; next != null; next = shownAs[at]) {
        at = next;
      }
      shownAs[key] = at;
    }
    return (rows, shownAs);
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
      case LogicalKeyboardKey.arrowRight when at >= 0 && rows[at].leaf:
        // В файл не входят: раскрывать нечего.
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowRight:
        // Вправо раскрывает, а раскрытую — уводит внутрь: то же, что в панели.
        if (_open.containsKey(widget.selected)) {
          _select(rows, at + 1);
        } else {
          unawaited(_expand(widget.selected));
        }
      case LogicalKeyboardKey.arrowLeft:
        if (_open.containsKey(widget.selected) && widget.selected != _root) {
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
    _choose(rows[at].path, rows[at].leaf);
    _show(at);
  }

  /// Подтянуть строку в обзор, если её не видно.
  void _show(int at) {
    if (!_scroll.hasClients) {
      return;
    }
    final line = _lineOf(FcTheme.of(context));
    final top = at * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      position.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      position.jumpTo(top + line - position.viewportDimension);
    }
  }

  /// Высота строки — та же, что у панели: строка и просвет под ней.
  static double _lineOf(FcTheme theme) => theme.metrics.rowHeight + theme.metrics.rowGap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final rows = _rows;

    return Focus(
      focusNode: _keys,
      // Плашка — та же, какой обведён раздел настроек: список в окне выглядит
      // одинаково, где бы он ни стоял.
      child: FcPlate(
        // Вплотную: курсор дерева упирается в края плашки, как строка в панели
        // упирается в её рамку.
        tight: true,
        child: ListView.builder(
          controller: _scroll,
          itemCount: rows.length,
          itemExtent: _lineOf(theme),
          itemBuilder: (context, index) => _row(theme, rows[index]),
        ),
      ),
    );
  }

  Widget _row(FcTheme theme, _Branch branch) {
    final metrics = theme.metrics;
    final chosen = branch.path == widget.selected;
    final opened = _open.containsKey(branch.path);
    final colors = theme.colors;
    final icons = theme.icons;
    final style = chosen ? theme.rowStyle.copyWith(color: colors.cursorText) : theme.rowStyle;

    // Знак раскрытия — **тот же глиф и тем же шрифтом**, что в дереве панели:
    // два разных шеврона в одном приложении человек видит сразу
    // (`docs/spec/panel-view-tree.md`, §4).
    final mark = String.fromCharCode(
      branch.leaf ? icons.file.codePoint : (opened ? icons.branchOpen.codePoint : icons.branchClosed.codePoint),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _keys.requestFocus();
        _choose(branch.path, branch.leaf);
        if (branch.leaf) {
          // В файл не входят: щелчок по нему только выбирает.
          return;
        }
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
        height: _lineOf(theme),
        color: chosen ? colors.cursorBackground : null,
        // Шаг вглубь — квадрат знака вместе с просветом: знак дочерней ветви
        // приходится серединой на середину родительского. То же, что в панели.
        padding: EdgeInsets.only(
          left: metrics.iconLeftPadding + branch.depth * (metrics.iconSize + metrics.treeMarkGap),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(
              width: metrics.iconSize,
              // По середине квадрата, а не по левому краю: глиф угла узкий.
              child: Center(
                child: Text(
                  mark,
                  style: TextStyle(
                    fontFamily: icons.fontFamily,
                    fontSize: metrics.fontSize,
                    color: chosen ? colors.iconSelected : colors.icon,
                  ),
                ),
              ),
            ),
            SizedBox(width: metrics.treeMarkGap),
            Flexible(
              child:
                  branch.head.isEmpty
                      ? Text(
                        branch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Набором строки панели, а не окна: это список
                        // объектов, и читается он теми же буквами, что список в
                        // панели.
                        style: style,
                      )
                      // Строка цепочки — той же подписью, что в панели: голова
                      // приглушена к фону под ней, длинная режется слева (§13).
                      : FcChainName(
                        head: branch.head,
                        name: branch.name,
                        style: style,
                        headStyle: style.copyWith(
                          color: Color.lerp(
                            style.color,
                            chosen ? colors.cursorBackground : colors.dialogListBackground,
                            0.45,
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ветвь на экране: адрес, имя и глубина.
class _Branch {
  const _Branch({required this.path, required this.name, required this.depth, this.head = '', this.leaf = false});

  final String path;
  final String name;
  final int depth;

  /// Имена каталогов, поглощённых строкой, через `/`; пусто — строка сама по
  /// себе.
  final String head;

  /// Файл: внутрь него не входят, и знака раскрытия у него нет.
  final bool leaf;
}
