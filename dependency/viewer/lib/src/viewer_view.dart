import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'viewer_screen.dart';

/// Показ файла: общий показ текста без права писать.
///
/// Вся видимая часть — в `FcCodeView`: рамка, поле, подсветка, фокус. Здесь
/// остаётся только то, чем просмотрщик отличается от редактора, — запрет на
/// правку, размер файла в заголовке и `Cmd-C`, отпущенная своей команде.
class ViewerView extends StatelessWidget {
  const ViewerView({super.key, required this.screen});

  final ViewerScreen screen;

  /// `Esc` закрывает экран, `Cmd-C` копирует нашей командой — она проходит
  /// через буфер обмена приложения и говорит человеку, что случилось. Оставь
  /// копирование виджету, оно сработало бы дважды и молча.
  static const FcCodeShortcuts _shortcuts = FcCodeShortcuts(released: {CodeShortcutType.esc, CodeShortcutType.copy});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: screen,
      builder:
          (context, _) => FcCodeView(
            controller: screen.controller,
            // Полный адрес, а не одно имя: файл может лежать в архиве или на
            // сервере, и по имени этого не видно. Размер — припиской.
            path: screen.node.displayPath,
            fileName: screen.node.name,
            trailing: formatBytesLong(screen.node.size),
            readOnly: true,
            wordWrap: screen.wordWrap,
            showLineNumbers: screen.showLineNumbers,
            shortcuts: _shortcuts,
          ),
    );
  }
}
