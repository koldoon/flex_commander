import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'place.dart';
import 'places_state.dart';

/// Боковая полоса избранного (`docs/spec/favorites-sidebar.md`, §2).
///
/// Та же рама, что у панели, с плашкой `Favorites` на верхней рамке; строки —
/// рецептом строки панели, имя — интерфейсным шрифтом. Ширину держит сама и
/// тянется за правый край.
class PlacesView extends StatefulWidget {
  const PlacesView({super.key, required this.state});

  final PlacesState state;

  @override
  State<PlacesView> createState() => _PlacesViewState();
}

class _PlacesViewState extends State<PlacesView> {
  final ScrollController _scroll = ScrollController();

  /// Строка, которую переставляют мышью; null — не переставляют.
  int? _dragging;

  /// Куда встанет переставляемое — позиция между строками.
  int? _dragTarget;

  /// Ширина в начале оттягивания края.
  double _resizeFrom = 0;

  PlacesState get state => widget.state;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Шаг строки — тот же, что у списка панели: «Icon size» делает строки
  /// выше и там, и здесь.
  double _rowHeight(FcMetrics metrics) => FileIconSize.listRow(metrics, AppScope.read(context).fileIcons);

  /// Позиция между строками под точкой списка: 0 — над первой, n — под
  /// последней.
  int _slotAt(double dy, FcMetrics metrics) {
    final y = dy + (_scroll.hasClients ? _scroll.offset : 0);
    return (y / _rowHeight(metrics)).round().clamp(0, state.places.length);
  }

  /// Нажатие — курсор сразу, по нажатию, а не по отпусканию: щелчок виден
  /// раньше, чем панель успеет уйти, а неудача оставляет курсор на месте,
  /// которое приглушилось. Тем же движением ввод уходит полосе — так
  /// зажигается и панель (`docs/spec/panel-views.md`, §9).
  void _down(Application app, int index) {
    state.moveCursor(index);
    if (app.view.activeArea != ViewportPosition.sidebar) {
      app.view.setFocus(ViewportPosition.sidebar);
    }
  }

  void _press(int index) {
    // `Cmd`-щелчок — в соседнюю панель, как «открыть рядом» в браузере
    // (`docs/spec/favorites-sidebar.md`, §5.1).
    final other = HardwareKeyboard.instance.isMetaPressed;
    state.open(index, other: other);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final app = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([state, app.view]),
      builder: (context, _) {
        final width = (state.width ?? metrics.sidebarWidth).clamp(metrics.sidebarMinWidth, metrics.sidebarMaxWidth);
        final focused = app.view.activeArea == ViewportPosition.sidebar;
        final dnd = app.dragAndDrop;

        Widget list(int? dropSlot) => _PlacesList(
          state: state,
          scroll: _scroll,
          focused: focused,
          dropSlot: _dragTarget ?? dropSlot,
          dragging: _dragging,
          onDown: (index) => _down(app, index),
          onPress: _press,
          onDragStart:
              (index) => setState(() {
                _dragging = index;
                _dragTarget = index;
              }),
          onDragUpdate: (dy) => setState(() => _dragTarget = _slotAt(dy, metrics)),
          onDragEnd: () {
            final from = _dragging;
            final to = _dragTarget;
            setState(() {
              _dragging = null;
              _dragTarget = null;
            });
            if (from != null && to != null) {
              state.move(from, to);
            }
          },
        );

        final body =
            dnd == null
                ? list(null)
                : dnd.target(
                  owner: state,
                  spotAt: (local) => DropSpot(destination: '${_slotAt(local.dy, metrics)}'),
                  onDrop: (spot, payload) async => _drop(app, int.tryParse(spot.destination), payload),
                  builder: (context, hovered) => list(hovered == null ? null : int.tryParse(hovered.destination)),
                );

        return SizedBox(
          width: width,
          child: Stack(
            children: [
              Positioned.fill(
                child: FcPanelFrame(
                  outerEdge: PanelOuterEdge.left,
                  // Плашка горит, пока ввод у полосы, — как у панели.
                  header: FcPathPlate(path: app.strings.tr('Favorites'), active: focused),
                  child: body,
                ),
              ),
              // Край тянется — как граница между панелями.
              Positioned(
                top: 0,
                bottom: 0,
                right: -metrics.resizeHandleWidth / 2,
                width: metrics.resizeHandleWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _resizeFrom = width,
                    onHorizontalDragUpdate: (details) {
                      _resizeFrom += details.delta.dx;
                      state.setWidth(_resizeFrom.clamp(metrics.sidebarMinWidth, metrics.sidebarMaxWidth));
                    },
                    onHorizontalDragEnd: (_) => state.saveWidth(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Бросили на полосу: каталоги и архивы — местами, с точки вставки.
  ///
  /// Ничего не копируется: это не панель, а список адресов. Файл местом не
  /// бывает — о нём говорит тост, а не молчание.
  Future<void> _drop(Application app, int? slot, DropPayload payload) async {
    final addresses = [
      for (final entry in payload.entries)
        if (!entry.isParent && entry.opensAsBranch) entry.displayPath,
      for (final path in payload.paths)
        if (_isDirectory(path)) path,
    ];
    if (addresses.isEmpty) {
      app.toasts.fail(app.strings.tr('Only directories go to the sidebar'));
      return;
    }
    var at = slot;
    for (final address in addresses) {
      final before = state.places.length;
      final index = state.add(address, at: at);
      if (state.places.length > before) {
        at = index + 1;
      }
    }
  }

  /// Пути из Finder — пути этой машины: спросить систему можно прямо здесь.
  static bool _isDirectory(String path) {
    try {
      return FileSystemEntity.isDirectorySync(path);
    } on FileSystemException {
      return false;
    }
  }
}

class _PlacesList extends StatelessWidget {
  const _PlacesList({
    required this.state,
    required this.scroll,
    required this.focused,
    required this.dropSlot,
    required this.dragging,
    required this.onDown,
    required this.onPress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final PlacesState state;
  final ScrollController scroll;
  final bool focused;
  final int? dropSlot;
  final int? dragging;
  final void Function(int index) onDown;
  final void Function(int index) onPress;
  final void Function(int index) onDragStart;
  final void Function(double dy) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final places = state.places;
    final slot = dropSlot;
    final icons = AppScope.read(context).fileIcons;
    final rowHeight = FileIconSize.listRow(metrics, icons);
    final iconSize = FileIconSize.of(metrics, icons);

    return LayoutBuilder(
      builder: (listContext, constraints) {
        return Stack(
          // Линия вставки стоит серединой на границе строк, и над первой
          // строкой половина её — выше списка. Обрезанная, она там
          // превращалась в огрызок; место есть — поле под плашкой.
          clipBehavior: Clip.none,
          children: [
            ListView.builder(
              controller: scroll,
              padding: EdgeInsets.zero,
              itemExtent: rowHeight,
              itemCount: places.length,
              itemBuilder: (context, index) {
                final renaming = state.renaming == index;
                final row = _PlaceRow(
                  state: state,
                  place: places[index],
                  iconSize: iconSize,
                  selected: focused && state.cursor == index,
                  renaming: renaming,
                );
                if (renaming) {
                  return row;
                }
                return RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      TapGestureRecognizer.new,
                      (recognizer) => recognizer.onTap = () => onPress(index),
                    ),
                    // Перестановка — после порога: щелчок остаётся переходом
                    // (`kFcDragSlop`).
                    FcVerticalDragRecognizer: GestureRecognizerFactoryWithHandlers<FcVerticalDragRecognizer>(
                      FcVerticalDragRecognizer.new,
                      (recognizer) {
                        recognizer
                          ..onStart = ((_) => onDragStart(index))
                          ..onUpdate = (details) {
                            // В точках списка, а не строки: прокрутку
                            // добавляет тот, кто ищет позицию.
                            final box = listContext.findRenderObject();
                            if (box is RenderBox) {
                              onDragUpdate(box.globalToLocal(details.globalPosition).dy);
                            }
                          }
                          ..onEnd = ((_) => onDragEnd())
                          ..onCancel = onDragEnd;
                      },
                    ),
                  },
                  // Нажатие — сразу, а не распознавателем: щелчок спорит с
                  // перестановкой, и тот сообщил бы о нажатии с задержкой.
                  child: Listener(onPointerDown: (_) => onDown(index), child: row),
                );
              },
            ),
            if (slot != null)
              Positioned(
                left: 0,
                right: 0,
                top: slot * rowHeight - (scroll.hasClients ? scroll.offset : 0) - _DropLine.height / 2,
                height: _DropLine.height,
                child: const _DropLine(),
              ),
          ],
        );
      },
    );
  }
}

/// Линия вставки: куда встанет брошенное или переставляемое.
class _DropLine extends StatelessWidget {
  const _DropLine();

  static const double height = 6;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final color = theme.colors.markedBar;
    final stroke = theme.metrics.strokeWidth;
    return Row(
      children: [
        const SizedBox(width: 4),
        Container(
          width: height,
          height: height,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: stroke * 1.5)),
        ),
        Expanded(child: Container(height: stroke * 2, color: color)),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.state,
    required this.place,
    required this.iconSize,
    required this.selected,
    required this.renaming,
  });

  final PlacesState state;
  final Place place;
  final double iconSize;
  final bool selected;
  final bool renaming;

  IconData _iconOf(FcIcons icons) => switch (PlaceAddress.kindOf(place.address)) {
    PlaceKind.home => icons.home,
    PlaceKind.desktop => icons.desktop,
    PlaceKind.documents => icons.documents,
    PlaceKind.downloads => icons.downloads,
    PlaceKind.applications => icons.applications,
    PlaceKind.volume => icons.volume,
    PlaceKind.server => icons.server,
    PlaceKind.archive => icons.archive,
    PlaceKind.folder => icons.folder,
  };

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final name = state.nameOf(place);
    final style = selected ? theme.uiStyle.copyWith(color: colors.cursorText) : theme.uiStyle;
    final row = Padding(
      padding: EdgeInsets.only(bottom: metrics.rowGap),
      child: DecoratedBox(
        decoration: BoxDecoration(color: selected ? colors.cursorBackground : null),
        child: Padding(
          padding: EdgeInsets.only(left: metrics.iconLeftPadding),
          // Без поправок строки панели (`rowContentVerticalNudge`,
          // `rowTextVerticalNudge`): они выверены под моноширинный шрифт
          // списка, а имя места набрано интерфейсным — с ними оно садилось на
          // полторы точки ниже середины подсветки. Выверено по чернилам
          // эталона `anchor_places.png`.
          child: Row(
            children: [
              SizedBox(
                width: iconSize,
                child: Center(
                  child: _PlaceIcon(
                    path: state.localPathOf(place),
                    glyph: _iconOf(theme.icons),
                    size: iconSize,
                    selected: selected,
                  ),
                ),
              ),
              SizedBox(width: metrics.iconGap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: metrics.cellPadding),
                  child: renaming ? _RenameField(state: state, initial: name) : FcTrimmedText(text: name, style: style),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Не дошли в прошлый раз — приглушено, но щёлкается: щелчок и есть новая
    // попытка (`docs/spec/favorites-sidebar.md`, §5.3).
    return state.isUnreachable(place) ? Opacity(opacity: 0.5, child: row) : row;
  }
}

/// Значок места: значок системы, если он включён и у места есть путь на этой
/// машине, иначе — глиф места.
///
/// Спрашивает ту же службу значков, что и строка панели, — каталогом с этим
/// путём: правила значков и флаг «System icons» действуют здесь так же, как
/// там. Берётся только **картинка**: глиф папки из правил хуже своего глифа
/// места — дома, загрузок, программ (`docs/spec/favorites-sidebar.md`, §2).
class _PlaceIcon extends StatefulWidget {
  const _PlaceIcon({required this.path, required this.glyph, required this.size, required this.selected});

  final String? path;
  final IconData glyph;
  final double size;
  final bool selected;

  @override
  State<_PlaceIcon> createState() => _PlaceIconState();
}

class _PlaceIconState extends State<_PlaceIcon> {
  ImageProvider? _picture;

  /// О чём спрашивали в последний раз: строки списка переиспользуются, и
  /// опоздавший ответ про чужое место не должен лечь на эту строку.
  String _askedFor = '';

  @override
  Widget build(BuildContext context) {
    _resolve(context);
    final picture = _picture;
    if (picture != null) {
      // Картинка как есть, без перекраски под курсором — как в панели.
      return Image(
        image: picture,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    final theme = FcTheme.of(context);
    return Text(
      String.fromCharCode(widget.glyph.codePoint),
      style: TextStyle(
        fontFamily: theme.icons.fontFamily,
        fontSize: theme.metrics.iconSize,
        color: widget.selected ? theme.colors.iconSelected : theme.colors.icon,
        height: 1,
      ),
    );
  }

  void _resolve(BuildContext context) {
    final path = widget.path;
    final icons = AppScope.read(context).fileIcons;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final key = '$path|${widget.size}|$ratio';
    if (key == _askedFor) {
      return;
    }
    _askedFor = key;
    _picture = null;
    if (path == null || icons == null) {
      return;
    }
    final slash = path.lastIndexOf('/');
    final entry = FileEntry(
      name: slash < 0 || slash == path.length - 1 ? path : path.substring(slash + 1),
      kind: EntryKind.directory,
      path: path,
      displayPath: path,
      realPath: path,
    );
    final answer = icons.resolve(entry, pixels: (widget.size * ratio).round(), stillWanted: () => mounted);
    _picture = _pictureOf(answer.now);
    answer.later?.then((icon) {
      if (mounted && key == _askedFor) {
        setState(() => _picture = _pictureOf(icon));
      }
    });
  }

  static ImageProvider? _pictureOf(FileIcon icon) => icon is IconPicture ? icon.image : null;
}

/// Имя места на месте подписи: `Enter` — принять, `Esc` — отказ.
class _RenameField extends StatefulWidget {
  const _RenameField({required this.state, required this.initial});

  final PlacesState state;
  final String initial;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  /// Ответ уже дан — второй не нужен: уход фокуса после `Enter` иначе принял
  /// бы имя дважды.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Щёлкнули мимо — как в Finder: набранное принимается.
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _done = true;
      widget.state.cancelRename();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commit() {
    if (_done) {
      return;
    }
    _done = true;
    widget.state.commitRename(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inputBackground,
        border: Border.all(color: colors.focusRing, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding - metrics.strokeWidth),
        child: Center(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            style: theme.uiStyle.copyWith(color: colors.inputText),
            cursorColor: colors.inputText,
            decoration: const InputDecoration.collapsed(hintText: null),
            onSubmitted: (_) => _commit(),
          ),
        ),
      ),
    );
  }
}
