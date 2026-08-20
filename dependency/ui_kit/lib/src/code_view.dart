import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'code_language.dart';
import 'code_shortcuts.dart';
import 'code_style.dart';
import 'fc_theme.dart';
import 'panel_frame.dart';

/// Показ текста во весь экран: та же рамка, что у панели, и текстовое поле во
/// всю её.
///
/// Один виджет на просмотрщик и на редактор — разница между ними в одном
/// [readOnly]. Раскладку, отрисовку, выделение и ввод берёт на себя
/// `re_editor`: это не надстройка над `TextField`, а свой движок, рассчитанный
/// на большой текст, и рисует он только то, что попало на экран.
class FcCodeView extends StatefulWidget {
  const FcCodeView({
    super.key,
    required this.controller,
    required this.path,
    required this.fileName,
    this.trailing,
    this.readOnly = false,
    this.wordWrap = false,
    this.showLineNumbers = false,
    this.shortcuts = const FcCodeShortcuts(),
  });

  /// Содержимое и курсор. Владеет им экран: сохранять или копировать просит
  /// команда, а она о виджетах ничего не знает.
  final CodeLineEditingController controller;

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
  final FcCodeShortcuts shortcuts;

  @override
  State<FcCodeView> createState() => _FcCodeViewState();
}

class _FcCodeViewState extends State<FcCodeView> {
  final FocusNode _focus = FocusNode(debugLabel: 'FcCodeView');

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
          focusNode: _focus,
          readOnly: widget.readOnly,
          wordWrap: widget.wordWrap,
          padding: EdgeInsets.symmetric(horizontal: theme.metrics.panelLeftPadding),
          style: codeStyle(theme, codeBaseStyle(theme), languageOf(widget.fileName)),
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
