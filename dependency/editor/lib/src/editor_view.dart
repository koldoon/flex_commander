import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_screen.dart';

/// Правка файла: общий показ текста с правом писать.
///
/// Вся видимая часть — в `FcCodeView`: рамка, поле, подсветка, фокус. Здесь
/// остаётся только то, чем редактор отличается от просмотрщика, — право писать
/// и знак несохранённого в заголовке.
class EditorView extends StatelessWidget {
  const EditorView({super.key, required this.screen});

  final EditorScreen screen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: screen,
      builder:
          (context, _) => FcCodeView(
            controller: screen.controller,
            path: screen.node.displayPath,
            fileName: screen.node.name,
            // Звёздочка — общепринятый знак несохранённого; ничего своего
            // выдумывать не нужно.
            trailing: screen.modified ? '•' : null,
            wordWrap: screen.wordWrap,
          ),
    );
  }
}
