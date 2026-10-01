import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'dialog_frame.dart';

/// Окна запущенных команд.
///
/// Ядро рисует рамку, заголовок и затемнение, а всё остальное берёт из
/// описания, которое даёт показавший окно, — [DialogSpec]. Так все окна выглядят одинаково, но
/// команда полностью распоряжается тем, что внутри, и меняет это по ходу
/// работы: ввод, ход выполнения, вопрос, ошибка.
class CommandDialogLayer extends StatefulWidget {
  const CommandDialogLayer({super.key, required this.app});

  final Application app;

  @override
  State<CommandDialogLayer> createState() => _CommandDialogLayerState();
}

class _CommandDialogLayerState extends State<CommandDialogLayer> {
  /// Где стоит каждое окно — по нему дочернее находит место у родителя
  /// (`docs/spec/child-dialogs.md`, §4.4).
  final Map<String, ValueNotifier<Rect?>> _places = {};

  @override
  void dispose() {
    for (final place in _places.values) {
      place.dispose();
    }
    super.dispose();
  }

  /// Забыть места закрытых окон.
  void _forgetClosed(List<OpenDialog> open) {
    final live = {for (final dialog in open) dialog.id};
    final gone = _places.keys.where((id) => !live.contains(id)).toList();
    for (final id in gone) {
      _places.remove(id)?.dispose();
    }
  }

  ValueNotifier<Rect?> _placeOf(String id) => _places.putIfAbsent(id, () => ValueNotifier<Rect?>(null));

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app.view,
      builder: (context, _) {
        final own = app.view.openDialogs;
        _forgetClosed(own);
        if (own.isEmpty) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            for (final dialog in own)
              DialogFrame(
                key: ValueKey(dialog.spec),
                title: dialog.spec.title,
                takesFocus: dialog.spec.takesFocus,
                area: dialog.spec.area,
                ownWidth: dialog.spec.ownWidth,
                hugsContent: dialog.spec.hugsContent,
                id: dialog.spec.id,
                resizable: dialog.spec.resizable,
                onSubmit: dialog.spec.onSubmit ?? () {},
                onDismiss: dialog.spec.onDismiss ?? () {},
                // Крестик — только там, где `Esc` и правда закрывает: иначе он
                // обещал бы то, чего окно не умеет.
                closable: dialog.spec.onDismiss != null,
                placed: _placeOf(dialog.id),
                anchor: switch (dialog.spec.parent) {
                  final parent? when own.any((open) => open.id == parent) => _placeOf(parent),
                  _ => null,
                },
                onTop: identical(dialog, own.last),
                // Клавиши, пока окно открыто, принадлежат ему целиком
                // (`docs/screens.md`), — и списку, который оно показывает,
                // тоже: курсор в нём ходит стрелками. Приложение об этом не
                // спросишь, оно знает только области, а окно областью не
                // бывает (`KeysScope`).
                //
                // Верхнему: окон бывает несколько одно над другим, и клавиши у
                // последнего показанного.
                child: DialogScope(
                  dialogId: dialog.id,
                  child: KeysScope(takesKeys: identical(dialog, own.last), child: dialog.spec.content),
                ),
              ),
          ],
        );
      },
    );
  }
}
