import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
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
    this.padding = EdgeInsets.zero,
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
  /// (`docs/spec/markdown-viewer.md`, §7).
  final int? activeBlock;

  /// Чем прочесть картинку по относительному пути; null — читать нечем, и
  /// вместо картинки показывается подпись.
  final FcImageResolver? resolveImage;

  final EdgeInsets padding;

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
  /// кадром. Проб ровно две: список мог и не доехать, но крутить его без конца
  /// хуже, чем показать приблизительно.
  void _reveal(int index) {
    if (!mounted) {
      return;
    }

    final target = _keys[index]?.currentContext;
    if (target != null) {
      unawaited(Scrollable.ensureVisible(target, alignment: 0.1, duration: const Duration(milliseconds: 120)));

      return;
    }

    if (_attempts >= 2 || !_scroll.hasClients) {
      return;
    }
    _attempts++;

    final position = _scroll.position;
    final blocks = widget.document.length;
    final share = blocks == 0 ? 0.0 : index / blocks;
    position.jumpTo((share * position.maxScrollExtent).clamp(0.0, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(index));
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

  Widget _blockAt(BuildContext context, int index) {
    final body =
        _built[index] ??= KeyedSubtree(
          key: _keys[index] ??= GlobalKey(),
          child: Padding(padding: widget.padding, child: _build(context, widget.document.nodes[index])),
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
      checkboxBuilder: null,
      bulletBuilder: null,
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
      final width = constraints.maxWidth.isFinite ? (constraints.maxWidth / 8).floorToDouble() * 8 : 0.0;
      if (width != _width) {
        _width = width;
        _built.clear();
      }

      return SelectionArea(
        child: ListView.builder(controller: _scroll, itemCount: widget.document.length, itemBuilder: _blockAt),
      );
    },
  );

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
