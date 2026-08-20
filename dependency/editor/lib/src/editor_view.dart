import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import 'editor_screen.dart';
import 'language.dart';

/// Правка файла: та же рамка, что у панели, и текстовое поле во всю её.
///
/// Раскладку, отрисовку и ввод берёт на себя `re_editor`: он не надстройка над
/// `TextField`, а свой движок, рассчитанный на большой текст. Подсветка у него
/// та же `re_highlight`, которой пользуется просмотрщик, поэтому цвета берутся
/// из одной карты (`syntaxTheme`) — и два экрана не расходятся в виде.
class EditorView extends StatefulWidget {
  const EditorView({super.key, required this.screen});

  final EditorScreen screen;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final FocusNode _focus = FocusNode(debugLabel: 'EditorView');

  @override
  void initState() {
    super.initState();
    // Фокус просится явно, а не через `autofocus`.
    //
    // К моменту, когда редактор появляется, фокус уже у обработчика
    // клавиатуры, и область считает, что хозяин есть, — просьбу `autofocus`
    // она отклоняет молча. Человек при этом видит текст, но курсора нет и
    // печатать некуда, пока он не ткнёт мышью.
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
    final colors = theme.colors;
    final base = TextStyle(fontFamily: theme.fonts.fixed, fontSize: theme.metrics.fontSize, color: colors.rowText);
    final language = languageOf(widget.screen.node.name);

    return ListenableBuilder(
      listenable: widget.screen,
      builder: (context, _) {
        return FcPanelFrame(
          outerEdge: PanelOuterEdge.both,
          header: FcPathPlate(
            path: widget.screen.node.displayPath,
            // Звёздочка — общепринятый знак несохранённого; ничего своего
            // выдумывать не нужно.
            trailing: widget.screen.modified ? '•' : null,
          ),
          child: Padding(
            padding: EdgeInsets.all(theme.metrics.scrollbarInset),
            child: CodeEditor(
              controller: widget.screen.controller,
              focusNode: _focus,
              wordWrap: widget.screen.wordWrap,
              padding: EdgeInsets.symmetric(horizontal: theme.metrics.panelLeftPadding),
              style: editorStyle(theme, base, language),
              // Встроенные сочетания редактора не должны отбирать клавиши у
              // экрана: `Esc`, `F2` и `F10` принадлежат командам, и ряд кнопок
              // обещает именно их.
              shortcutsActivatorsBuilder: const EditorShortcuts(),
            ),
          ),
        );
      },
    );
  }
}

/// Оформление редактора из темы приложения.
///
/// Языков ровно один — тот, что опознан по имени файла: регистрировать все две
/// сотни ради одного файла незачем.
///
/// **Своего фона у редактора нет.** Фон панели (`panelBackground`) — это белый
/// с прозрачностью пять процентов поверх фона окна, и рисует его рамка
/// (`FcPanelFrame`). Положить тот же цвет ещё раз внутри редактора значит
/// сложить прозрачности: получается полтона разницы с панелью — ровно то, что
/// видно глазом и не видно в коде. `null` здесь означает «не красить».
CodeEditorStyle editorStyle(FcTheme theme, TextStyle base, String? language) {
  final colors = theme.colors;
  final mode = language == null ? null : builtinAllLanguages[language];

  return CodeEditorStyle(
    fontFamily: base.fontFamily,
    fontSize: base.fontSize,
    textColor: colors.rowText,
    cursorColor: colors.markedBar,
    selectionColor: colors.inputSelection,
    codeTheme: CodeHighlightTheme(
      languages: {if (mode != null) language!: CodeHighlightThemeMode(mode: mode)},
      theme: syntaxTheme(colors, base),
    ),
  );
}

/// Сочетания редактора без тех, что принадлежат экрану.
///
/// Открытый класс, а не частный: то, какие клавиши редактор **отпускает**, —
/// это решение, а не подробность, и проверяется оно тестом.
class EditorShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const EditorShortcuts();

  /// Клавиши, которые принадлежат экрану, а не тексту.
  static const Set<CodeShortcutType> released = {CodeShortcutType.esc};

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (released.contains(type)) {
      // `Esc` закрывает редактор — и, если есть несохранённое, спрашивает.
      // Утонув в виджете, он оставил бы человека в редакторе без выхода.
      return const [];
    }
    return super.build(type);
  }
}
