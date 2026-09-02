import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'text_viewer_screen.dart';

/// Показ файла: общий показ текста без права писать.
///
/// Вид **один на оба места** — во весь экран и в области панели. Разница в
/// раме (внешние края) и в фокусе (в панель его отдают, только когда в показ
/// вошли), и обе берутся из [ViewerContent.place] и у самой области. Двух
/// видов одного и того же не заводим: они однажды разойдутся.
///
/// Вся видимая часть — в `FcTextView`: рамка, поле, подсветка, фокус. Здесь
/// остаётся только то, чем просмотрщик отличается от редактора, — запрет на
/// правку, размер файла в заголовке и `Cmd-C`, отпущенная своей команде.
///
/// Курсора в нём не видно: `FcTextView` прячет его в режиме чтения.
class TextViewerView extends StatelessWidget {
  const TextViewerView({super.key, required this.screen});

  final TextViewerScreen screen;

  /// `Esc` закрывает экран, `Cmd-C` копирует нашей командой — она проходит
  /// через буфер обмена приложения и говорит человеку, что случилось. Оставь
  /// копирование виджету, оно сработало бы дважды и молча.
  ///
  /// Стрелки крутят текст, а не ходят курсором: курсора здесь не видно, и
  /// шагать им по строкам, пока экран стоит, некому. Так листают Lister,
  /// просмотрщик Far и `less`.
  static const FcTextShortcuts _shortcuts = FcTextShortcuts(
    released: {CodeShortcutType.esc, CodeShortcutType.copy},
    scrollsByArrows: true,
  );

  /// Внешние края рамы: во весь экран оба, в панели — её сторона.
  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }
    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Приложение спрашиваем только там, где оно и правда нужно: показу во весь
    // экран рама и фокус известны и так — оба края внешние, ввод его. В
    // области панели всё иначе: сторона рамы и фокус зависят от того, где он
    // стоит и вошли ли в него.
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder:
          (context, _) => FcTextView(
            controller: screen.controller,
            finder: screen.finder,
            // Полный адрес, а не одно имя: файл может лежать в архиве или на
            // сервере, и по имени этого не видно. Размер — припиской.
            path: screen.entry.path,
            fileName: screen.entry.name,
            trailing: formatBytesLong(screen.entry.size),
            readOnly: true,
            wordWrap: screen.wordWrap,
            showLineNumbers: screen.showLineNumbers,
            shortcuts: _shortcuts,
            outerEdge: _edgeOf(app),
            // Во весь экран фокус нужен сразу; в панели — только когда в показ
            // вошли: пока курсор в файлах, стрелки принадлежат ему.
            focused: app == null || app.view.takesKeys(screen),
          ),
    );
  }
}
