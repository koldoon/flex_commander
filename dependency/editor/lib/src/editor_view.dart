import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_screen.dart';

/// Правка файла: общий показ текста с правом писать.
///
/// Вся видимая часть — в `FcTextView`: рамка, поле, подсветка, фокус. Здесь
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
          (context, _) => FcTextView(
            controller: screen.controller,
            finder: screen.finder,
            path: screen.node.displayPath,
            fileName: screen.node.name,
            // Звёздочка — общепринятый знак несохранённого; ничего своего
            // выдумывать не нужно. У файла только на чтение её место занимает
            // прямая надпись: несохранённому там взяться неоткуда.
            trailing:
                screen.readOnly
                    ? 'read-only'
                    : screen.modified
                    ? '•'
                    : null,
            readOnly: screen.readOnly,
            wordWrap: screen.wordWrap,
            showLineNumbers: screen.showLineNumbers,
          ),
    );
  }
}
