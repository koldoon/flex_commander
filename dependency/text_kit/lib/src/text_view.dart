import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'code_language.dart';
import 'text_finder.dart';
import 'text_shortcuts.dart';
import 'text_style.dart';

/// Показ текста во весь экран: та же рамка, что у панели, и текстовое поле во
/// всю её.
///
/// Один виджет на просмотрщик и на редактор — разница между ними в одном
/// [readOnly]. Раскладку, отрисовку, выделение и ввод берёт на себя
/// `re_editor`: это не надстройка над `TextField`, а свой движок, рассчитанный
/// на большой текст, и рисует он только то, что попало на экран.
class FcTextView extends StatefulWidget {
  const FcTextView({
    super.key,
    required this.controller,
    this.finder,
    required this.path,
    required this.fileName,
    this.trailing,
    this.readOnly = false,
    this.wordWrap = false,
    this.showLineNumbers = false,
    this.shortcuts = const FcTextShortcuts(),
    this.outerEdge = PanelOuterEdge.both,
    this.focused = true,
    this.startAtLine,
    this.onTopLine,
  });

  /// Содержимое и курсор. Владеет им экран: сохранять или копировать просит
  /// команда, а она о виджетах ничего не знает.
  final CodeLineEditingController controller;

  /// Поиск — им же владеет экран. Поле подсвечивает по нему **все** совпадения
  /// само; своей панели поиска мы не рисуем, строку спрашивает окно команды.
  final FcTextFinder? finder;

  /// Полный адрес файла — в заголовке. Не одно имя: файл может лежать в архиве
  /// или на сервере, и по имени этого не видно.
  final String path;

  /// Имя файла: по нему опознаётся язык подсветки.
  final String fileName;

  /// Приписка в заголовке: размер у просмотрщика, знак несохранённого у
  /// редактора.
  final String? trailing;

  final bool readOnly;
  final bool wordWrap;
  final bool showLineNumbers;

  /// Какие клавиши поле отпускает экрану.
  final FcTextShortcuts shortcuts;

  /// Какие края рамки внешние. Во весь экран — оба; в области панели — тот же,
  /// что был бы у неё самой, иначе показ выпадал бы из раскладки.
  final PanelOuterEdge outerEdge;

  /// Просить ли системный фокус.
  ///
  /// Полноэкранному он нужен всегда: стрелки и страницы листают текст, а это
  /// дело показа, а не команд. Быстрому просмотру — только когда в него вошли:
  /// пока курсор в файловой панели, листать нечего, и забирать у неё фокус
  /// нельзя.
  final bool focused;

  /// С какой строки открыть текст; null — с начала.
  ///
  /// Так переключение вида не теряет место чтения: показ markdown переводит
  /// блок документа в строку исходника и открывает её сверху
  /// (`docs/spec/markdown-viewer.md`, §8).
  ///
  /// Применяется **один раз**, при появлении показа.
  final int? startAtLine;

  /// Сверху видно другую строку.
  ///
  /// Курсор для этого не годится: в показе стрелки крутят текст, а не водят
  /// курсор, и он остаётся там, где был.
  final void Function(int line)? onTopLine;

  @override
  State<FcTextView> createState() => _FcTextViewState();
}

class _FcTextViewState extends State<FcTextView> {
  final FocusNode _focus = FocusNode(debugLabel: 'FcTextView');

  /// Своя прокрутка: ею открывают текст на нужной строке.
  final CodeScrollController _scroll = CodeScrollController();

  /// Видимые строки — их считает само поле, а отдаёт через указатель слева.
  CodeIndicatorValueNotifier? _visible;

  /// Высота строки; 0 — ещё не рисовали.
  double _lineHeight = 0;

  @override
  void initState() {
    super.initState();
    // Фокус просится явно, а не через `autofocus`.
    //
    // К моменту, когда экран появляется, фокус уже у обработчика клавиатуры, и
    // область считает, что хозяин есть, — просьбу `autofocus` она отклоняет
    // молча. Человек при этом видит текст, но курсора нет и ни печатать, ни
    // листать нечем, пока он не ткнёт мышью.
    //
    // После кадра: до него узла ещё нет в дереве фокуса.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.focused) {
        _focus.requestFocus();
      }
      // Вторым кадром: до первого высоты строки ещё не знает никто.
      final start = widget.startAtLine;
      if (start != null && start > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openAt(start));
      }
    });
  }

  @override
  void didUpdateWidget(FcTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) {
      return;
    }
    // Фокус ходит за областью: вошли в показ — он ему, ушли — отдаёт обратно.
    // Отдаёт, а не держит про запас: пока он у поля, стрелки листают текст, а
    // они нужны курсору в панели.
    if (widget.focused) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _visible?.removeListener(_onVisible);
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Поле пересчитало видимое: запомнить высоту строки и сказать, что сверху.
  ///
  /// Слушатель зовут во время раскладки, поэтому здесь только чтение и
  /// сообщение наружу — ни `setState`, ни прокрутки.
  void _onVisible() {
    final paragraphs = _visible?.value?.paragraphs;
    if (paragraphs == null || paragraphs.isEmpty) {
      return;
    }
    _lineHeight = paragraphs.first.height;
    widget.onTopLine?.call(paragraphs.first.index);
  }

  /// Открыть текст на строке [line].
  ///
  /// Прокруткой в пикселях, а не «показать позицию»: та подводит строку к
  /// ближнему краю — прыжок вперёд оставил бы её внизу, и место чтения уехало
  /// бы на экран. Высота строки здесь одна на все: перенос по словам в показе
  /// выключен.
  void _openAt(int line) {
    if (!mounted || _lineHeight <= 0) {
      return;
    }
    final scroller = _scroll.verticalScroller;
    if (!scroller.hasClients) {
      return;
    }
    scroller.jumpTo((line * _lineHeight).clamp(0.0, scroller.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    // Та же рамка и та же плашка, что у файловой панели: экран занимает её
    // место и обязан выглядеть так же. Оба края внешние — он во всю ширину
    // окна.
    return FcPanelFrame(
      outerEdge: widget.outerEdge,
      // Плашка приглушается по тому же правилу, что у файловой панели: она
      // говорит, кому сейчас достаются клавиши. Во весь экран показ их и
      // забирает, а в области панели — только когда в него вошли.
      header: FcPathPlate(path: widget.path, trailing: widget.trailing, active: widget.focused),
      // Отступ здесь — только для полос прокрутки: они стоят по краю панели, а
      // текст отодвигают уже свои поля.
      child: Padding(
        padding: EdgeInsets.all(theme.metrics.scrollbarInset),
        child: CodeEditor(
          controller: widget.controller,
          scrollController: _scroll,
          findController: widget.finder?.findController,
          focusNode: _focus,
          readOnly: widget.readOnly,
          // В режиме чтения курсора не видно: править нечего, а мигающая
          // палочка обещает ввод. Позицию он всё равно держит — ею листают
          // стрелки и страницы, — просто не мозолит глаза.
          showCursorWhenReadOnly: false,
          wordWrap: widget.wordWrap,
          padding: EdgeInsets.symmetric(horizontal: theme.metrics.panelLeftPadding),
          style: textViewStyle(theme, textBaseStyle(theme), languageOf(widget.fileName)),
          // Указатель нужен и без номеров строк: только через него поле
          // говорит, что сейчас видно. Без номеров он пустой и места не
          // занимает.
          indicatorBuilder: _indicator,
          shortcutsActivatorsBuilder: widget.shortcuts,
        ),
      ),
    );
  }

  /// Указатель слева: номера строк, если их просили, и подписка на видимое.
  Widget _indicator(
    BuildContext context,
    CodeLineEditingController controller,
    CodeChunkController chunkController,
    CodeIndicatorValueNotifier notifier,
  ) {
    if (!identical(_visible, notifier)) {
      _visible?.removeListener(_onVisible);
      _visible = notifier..addListener(_onVisible);
    }

    if (!widget.showLineNumbers) {
      return const SizedBox.shrink();
    }

    return _lineNumbers(context, controller, chunkController, notifier);
  }

  /// Номера строк слева. Цвет библиотека берёт от текста поля с прозрачностью
  /// — то есть из нашей темы.
  Widget _lineNumbers(
    BuildContext context,
    CodeLineEditingController controller,
    CodeChunkController chunkController,
    CodeIndicatorValueNotifier notifier,
  ) => Padding(
    padding: EdgeInsets.only(right: FcTheme.of(context).metrics.cellPadding),
    child: DefaultCodeLineNumber(controller: controller, notifier: notifier),
  );
}
