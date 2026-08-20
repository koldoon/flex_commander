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

  @override
  State<FcTextView> createState() => _FcTextViewState();
}

class _FcTextViewState extends State<FcTextView> {
  final FocusNode _focus = FocusNode(debugLabel: 'FcTextView');

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
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    // Та же рамка и та же плашка, что у файловой панели: экран занимает её
    // место и обязан выглядеть так же. Оба края внешние — он во всю ширину
    // окна.
    return FcPanelFrame(
      outerEdge: PanelOuterEdge.both,
      header: FcPathPlate(path: widget.path, trailing: widget.trailing),
      // Отступ здесь — только для полос прокрутки: они стоят по краю панели, а
      // текст отодвигают уже свои поля.
      child: Padding(
        padding: EdgeInsets.all(theme.metrics.scrollbarInset),
        child: CodeEditor(
          controller: widget.controller,
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
          indicatorBuilder: widget.showLineNumbers ? _lineNumbers : null,
          shortcutsActivatorsBuilder: widget.shortcuts,
        ),
      ),
    );
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
