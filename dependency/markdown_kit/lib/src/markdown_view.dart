import 'dart:async';
import 'dart:math' as math;

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show SelectionArea, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_document.dart';
import 'markdown_fenced_builder.dart';
import 'markdown_image.dart';
import 'markdown_style.dart';

/// Свёрстанный markdown — списком блоков, строящимся по мере показа.
///
/// Библиотечный `Markdown` собирает все виджеты разом и кладёт их в
/// `ListView(children:)`, а не в `ListView.builder`. Здесь документ разрезан по
/// узлам верхнего уровня, и блок строится тогда, когда до него долистали
/// (`docs/spec/markdown-viewer.md`, §5).
class FcMarkdownView extends StatefulWidget {
  const FcMarkdownView({
    super.key,
    required this.document,
    this.blocks = const <MarkdownBlockSpec>[],
    this.onTapLink,
    this.controller,
    this.activeBlock,
    this.resolveImage,
    this.blockPadding = EdgeInsets.zero,
    this.contentPadding = EdgeInsets.zero,
    this.contentWidthFactor = 1,
    this.headingSpacing = 0,
    this.autofocus = false,
    this.startAtBlock,
    this.onTopBlock,
  });

  final FcMarkdownDocument document;

  /// Чем рисовать врезки ```` ```<язык> ````; пусто — все остаются врезками
  /// кода, и это законный вид документа.
  final List<MarkdownBlockSpec> blocks;

  /// Нажали на ссылку: текст, адрес, подпись.
  final void Function(String text, String? href, String title)? onTapLink;

  final ScrollController? controller;

  /// Блок, в котором стоит найденное; null — не ищут или не нашлось.
  ///
  /// Показ подводит к нему список и подсвечивает его целиком. Целиком, а не
  /// слово: подсветить слово внутри свёрстанного абзаца значило бы
  /// перехватывать построение всех текстовых тегов
  /// (`docs/spec/markdown-viewer.md`, §9).
  final int? activeBlock;

  /// Чем прочесть картинку по относительному пути; null — читать нечем, и
  /// вместо картинки показывается подпись.
  final FcImageResolver? resolveImage;

  /// Отступ **каждого** блока: им разносят абзацы между собой.
  final EdgeInsets blockPadding;

  /// Отступ всего документа — сверху и снизу один раз, а не у каждого блока.
  ///
  /// Документ должен читаться документом, а не сплошным текстом от края до
  /// края: поля сверху и снизу для того и нужны.
  final EdgeInsets contentPadding;

  /// Какую долю ширины занимает текст; 1 — всю.
  ///
  /// Длинная строка читается плохо: глаз теряет начало следующей. Поля по краям
  /// дают колонку разумной ширины, а прокрутка при этом остаётся во всю
  /// область — хватать её у самого края привычнее.
  final double contentWidthFactor;

  /// Просить ли клавиши себе.
  ///
  /// Документ листают с клавиатуры — стрелками, страницами, `Home` и `End`.
  /// Без фокуса нажатие не дошло бы до показа вовсе, а нажатие без ответа —
  /// ошибка.
  final bool autofocus;

  /// С какого блока открыть документ; null — с начала.
  ///
  /// Так `F5` не теряет место чтения: исходник и свёрстанный вид разной длины,
  /// и общего у них только «какой блок сейчас сверху»
  /// (`docs/spec/markdown-viewer.md`, §8).
  ///
  /// Применяется **один раз**, при появлении показа: иначе любая перерисовка
  /// отбрасывала бы человека назад.
  final int? startAtBlock;

  /// Сверху видно другой блок.
  ///
  /// Спрашивается по концу прокрутки, а не на каждый пиксель: считать это
  /// приходится по построенным блокам, а место чтения нужно знать только к
  /// моменту переключения вида.
  final void Function(int block)? onTopBlock;

  /// Сколько воздуха добавить **над** заголовком.
  ///
  /// Сверху, а не снизу: заголовок принадлежит тому, что под ним, и без отбивки
  /// сверху он сливается с концом предыдущего раздела. Чем крупнее заголовок,
  /// тем больше отбивка — так отличают часть от подраздела, не читая.
  final double headingSpacing;

  @override
  State<FcMarkdownView> createState() => _FcMarkdownViewState();
}

class _FcMarkdownViewState extends State<FcMarkdownView> implements MarkdownBuilderDelegate {
  /// Построенные блоки: номер узла → виджет.
  ///
  /// Однажды построенный остаётся: виджет дёшев, а строить его заново на каждую
  /// прокрутку значило бы разбирать подсветку по десять раз.
  final Map<int, Widget> _built = {};

  /// Распознаватели нажатий на ссылки — их заводим мы, значит нам и освобождать.
  final List<GestureRecognizer> _recognizers = [];

  /// Ширина, под которую построены блоки; меняется — строим заново.
  double _width = 0;

  /// Ключи построенных блоков — по ним показ подводит список к найденному.
  final Map<int, GlobalKey> _keys = {};

  /// Свой контроллер, если снаружи не дали: без него не подвести список.
  ScrollController? _own;
  ScrollController get _scroll => widget.controller ?? (_own ??= ScrollController());

  /// Сколько раз пробовали подвести список к блоку, который ещё не построен.
  int _attempts = 0;

  MarkdownStyleSheet? _style;

  /// Блок, с которого список начинается, — точка отсчёта прокрутки.
  ///
  /// Не «подвести список к блоку», а **начать с него**: подвод — это прикидка
  /// «доля от всей длины», а длину ленивый список знает только по построенному.
  /// На неровном документе прикидка промахивается, список прыгает несколько
  /// кадров подряд и доезжает уже плавностью — человек видит, как показ куда-то
  /// едет сам. Точка отсчёта ставит место сразу и точно
  /// (`docs/spec/markdown-viewer.md`, §8).
  late final int _origin = (widget.startAtBlock ?? 0).clamp(0, math.max(0, widget.document.length - 1));

  /// Ключ середины: с него виджет прокрутки ведёт отсчёт.
  final GlobalKey _centre = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reset();
  }

  @override
  void didUpdateWidget(FcMarkdownView old) {
    super.didUpdateWidget(old);
    if (!identical(old.document, widget.document) || !identical(old.blocks, widget.blocks)) {
      _reset();
    }
    if (widget.activeBlock != old.activeBlock && widget.activeBlock != null) {
      _attempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(widget.activeBlock!));
    }
  }

  /// Подвести список к блоку.
  ///
  /// Построенный блок показывается точно; непостроенный сперва подводится
  /// примерно — по его доле в документе, — и показывается точно следующим
  /// кадром. Проб не больше трёх: список мог и не доехать, но крутить его без
  /// конца хуже, чем показать приблизительно.
  ///
  /// [duration] — за сколько доехать; `Duration.zero` ставит сразу, без
  /// плавности.
  void _reveal(int index, {double alignment = 0.1, Duration duration = const Duration(milliseconds: 120)}) {
    if (!mounted) {
      return;
    }

    final target = _keys[index]?.currentContext;
    if (target != null) {
      unawaited(Scrollable.ensureVisible(target, alignment: alignment, duration: duration));

      return;
    }

    if (_attempts >= 3 || !_scroll.hasClients) {
      return;
    }
    _attempts++;

    final position = _scroll.position;
    final blocks = widget.document.length;
    final share = blocks == 0 ? 0.0 : index / blocks;
    final from = position.minScrollExtent;
    position.jumpTo((from + share * (position.maxScrollExtent - from)).clamp(from, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(index, alignment: alignment, duration: duration));
  }

  /// Какой блок сейчас сверху.
  ///
  /// Считается по построенным: непостроенных на экране и нет. Берём тот, чей
  /// низ ещё под верхней кромкой, — то есть первый, который человек видит.
  int? _topBlock() {
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return null;
    }

    int? best;
    var bestTop = double.infinity;

    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + box.size.height <= 0) {
        continue;
      }
      if (top < bestTop) {
        bestTop = top;
        best = entry.key;
      }
    }

    return best;
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _own?.dispose();
    super.dispose();
  }

  void _reset() {
    _built.clear();
    _keys.clear();
    _style = null;
    _disposeRecognizers();
  }

  void _disposeRecognizers() {
    final taken = [..._recognizers];
    _recognizers.clear();
    for (final recognizer in taken) {
      recognizer.dispose();
    }
  }

  /// Оформление: наше поверх библиотечного запасного.
  ///
  /// Запасной нужен целиком: наш набор неполный, и поля, которых в нём нет
  /// (отступы списков, цитаты, разделители), берутся оттуда. Так делает и сама
  /// библиотека, и окно обновления выглядит от этого ровно как прежде.
  MarkdownStyleSheet _styleOf(BuildContext context) =>
      _style ??= MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(textScaler: MediaQuery.textScalerOf(context)).merge(fcMarkdownStyle(FcTheme.of(context)));

  /// Отбивка над заголовком и над чертой; 0 — обычный блок.
  ///
  /// Первому блоку она не нужна: над ним и так поле документа.
  double _topGap(int index) {
    if (index == 0 || widget.headingSpacing <= 0) {
      return 0;
    }
    final node = widget.document.nodes[index];
    final tag = node is md.Element ? node.tag : '';

    return switch (tag) {
      'h1' || 'h2' => widget.headingSpacing,
      'h3' || 'h4' => widget.headingSpacing * 0.6,
      // Черта делит части наравне с заголовком, и воздух ей нужен по той же
      // причине: вплотную к предыдущему абзацу она читается его подчёркиванием.
      'h5' || 'h6' || 'hr' => widget.headingSpacing * 0.4,
      _ => 0,
    };
  }

  Widget _blockAt(BuildContext context, int index) {
    final body =
        _built[index] ??= KeyedSubtree(
          key: _keys[index] ??= GlobalKey(),
          child: Padding(
            padding: widget.blockPadding.copyWith(top: widget.blockPadding.top + _topGap(index)),
            child: _build(context, widget.document.nodes[index]),
          ),
        );

    if (index != widget.activeBlock) {
      return body;
    }

    // Найденное видно подложкой: слово внутри свёрстанного абзаца подсветить
    // нечем, а блок целиком человек находит взглядом сразу.
    return ColoredBox(color: FcTheme.of(context).colors.markedBackground, child: body);
  }

  Widget _build(BuildContext context, md.Node node) {
    final builder = MarkdownBuilder(
      delegate: this,
      // Выделение даёт `SelectionArea` снаружи: так оно берёт весь документ, а
      // не каждый блок по отдельности.
      selectable: false,
      styleSheet: _styleOf(context),
      imageDirectory: null,
      imageBuilder: (uri, title, alt) => FcMarkdownImage(uri: uri, alt: alt ?? '', resolve: widget.resolveImage),
      // Флажок списка задач — наш, а не значок Material: тот рисуется чёрным
      // и в тёмной теме выглядит дырой. Нажать его нельзя: документ
      // показывают, а не правят (`docs/spec/markdown-viewer.md`, §6).
      //
      // `Align` обязателен: показ ставит значок пункта в коробку жёсткой
      // ширины (`builder.dart:435`), и без него флажок растягивался бы поперёк
      // неё — квадратик выходил вдвое шире, чем выше.
      //
      // К правому краю колонки — туда же, куда точка и номер: зазор до текста
      // у всех маркеров один, и колонка читается колонкой.
      checkboxBuilder:
          (checked) => Padding(
            padding: _styleOf(context).listBulletPadding ?? EdgeInsets.zero,
            child: Align(alignment: Alignment.centerRight, child: FcCheckboxMark(value: checked)),
          ),
      // Значок пункта — свой, ради выключки. Показ прижимает номер вправо, а
      // точку центрует в колонке маркера: у точки выходит втрое больший зазор
      // до текста, и на глаз она висит сама по себе. Все маркеры — вправо, к
      // одному краю (`docs/spec/markdown-viewer.md`, §6).
      bulletBuilder:
          (parameters) => Text(
            parameters.style == BulletStyle.unorderedList ? '•' : '${parameters.index + 1}.',
            textAlign: TextAlign.right,
            style: _styleOf(context).listBullet,
          ),
      builders: {'pre': FcFencedBlockBuilder(blocks: widget.blocks, maxWidth: _width)},
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
    );

    final children = builder.build([node]);

    return switch (children.length) {
      0 => const SizedBox.shrink(),
      1 => children.single,
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Округляем: иначе перетаскивание разделителя пересобирало бы документ
      // на каждый пиксель.
      final available = constraints.maxWidth.isFinite ? (constraints.maxWidth / 8).floorToDouble() * 8 : 0.0;
      final factor = widget.contentWidthFactor.clamp(0.1, 1.0);
      // Поля по краям — отступом списка, а не рамкой вокруг него: полоса
      // прокрутки должна остаться у края области, а не ехать вместе с текстом.
      final side = (available * (1 - factor) / 2).floorToDouble();
      final width = available - side * 2;

      if (width != _width) {
        _width = width;
        _built.clear();
      }

      return Focus(
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: SelectionArea(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: _noteTopBlock,
            child: CustomScrollView(
              controller: _scroll,
              // Отсчёт — от блока, с которого читают: всё, что выше него, уходит
              // в отрицательную часть прокрутки и строится, только если туда
              // поднимутся.
              center: _centre,
              slivers: [
                if (_origin > 0)
                  SliverPadding(
                    // Поле документа сверху — над **первым** блоком, а он здесь.
                    padding: EdgeInsets.only(top: widget.contentPadding.top, left: side, right: side),
                    sliver: SliverList(
                      // Отсчёт вверх: нулевой ребёнок — блок прямо над началом.
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _blockAt(context, _origin - 1 - index),
                        childCount: _origin,
                      ),
                    ),
                  ),
                SliverPadding(
                  key: _centre,
                  padding: EdgeInsets.only(
                    // А если начинают с самого начала, то первый блок — здесь.
                    top: _origin == 0 ? widget.contentPadding.top : 0,
                    bottom: widget.contentPadding.bottom,
                    left: side,
                    right: side,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _blockAt(context, _origin + index),
                      childCount: widget.document.length - _origin,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// Докрутили — запомнить, что теперь сверху.
  bool _noteTopBlock(ScrollEndNotification notification) {
    if (widget.onTopBlock != null) {
      // Следующим кадром: прыжок сообщает о конце прокрутки **до** того, как
      // список переложен, и по горячим следам сверху виден ещё старый блок.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final top = _topBlock();
        if (top != null) {
          widget.onTopBlock?.call(top);
        }
      });
    }

    // `false`: уведомление наше только к сведению, пусть идёт дальше.
    return false;
  }

  /// Прокрутка клавишами: документ листают так же, как показ текста.
  ///
  /// Стрелки идут строками, страницы — почти экраном (с нахлёстом в десятую
  /// часть, чтобы не терять место чтения), `Home` и `End` — к краям.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = _scroll.position;
    final page = position.viewportDimension * 0.9;

    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => position.pixels + _lineStep,
      LogicalKeyboardKey.arrowUp => position.pixels - _lineStep,
      LogicalKeyboardKey.pageDown || LogicalKeyboardKey.space => position.pixels + page,
      LogicalKeyboardKey.pageUp => position.pixels - page,
      _ => null,
    };

    if (event.logicalKey == LogicalKeyboardKey.home || event.logicalKey == LogicalKeyboardKey.end) {
      _toEdge(end: event.logicalKey == LogicalKeyboardKey.end);

      return KeyEventResult.handled;
    }

    if (target == null) {
      return KeyEventResult.ignored;
    }

    _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));

    return KeyEventResult.handled;
  }

  /// В начало или в конец документа.
  ///
  /// Одним прыжком не выходит: у ленивого списка предел прокрутки — **оценка**
  /// по уже построенному, и прыжок в неё строит следующий кусок, после чего
  /// предел отодвигается. Поэтому прыгаем, пока он двигается. Край здесь и
  /// правда край: начало — `minScrollExtent`, а не ноль, потому что отсчёт
  /// идёт от блока, с которого открыли.
  void _toEdge({required bool end, int attempts = 0}) {
    if (!mounted || !_scroll.hasClients) {
      return;
    }

    final position = _scroll.position;
    final target = end ? position.maxScrollExtent : position.minScrollExtent;
    if ((position.pixels - target).abs() < 0.5) {
      return;
    }

    position.jumpTo(target);
    if (attempts >= _edgeAttempts) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEdge(end: end, attempts: attempts + 1));
  }

  /// Сколько раз догоняем убегающий край.
  ///
  /// Оценка пересчитывается по средней высоте построенного и с каждым разом
  /// точнее; десятка хватает с запасом, а без предела опечатка в расчёте
  /// крутила бы список вечно.
  static const int _edgeAttempts = 10;

  /// Шаг стрелки. Три строки: по одной документ листать утомительно, а
  /// половиной экрана — уже страница.
  static const double _lineStep = 56;

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()..onTap = () => widget.onTapLink?.call(text, href, title);
    _recognizers.add(recognizer);

    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) =>
      TextSpan(style: styleSheet.code, text: code.replaceAll(RegExp(r'\n$'), ''));
}
