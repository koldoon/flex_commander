import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// Встроенные сочетания текстового поля без тех, что принадлежат экрану.
///
/// Открытый класс, а не частный: то, какие клавиши поле **отпускает**, — это
/// решение, а не подробность, и проверяется оно тестом.
///
/// `Esc` отпускают оба экрана: он закрывает их, и, утонув в виджете, оставил бы
/// человека внутри без выхода. Просмотрщик отпускает ещё и копирование — у него
/// на `Cmd-C` стоит своя команда, которая говорит, что случилось.
class FcCodeShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const FcCodeShortcuts({this.released = const {CodeShortcutType.esc}});

  /// Клавиши, которые принадлежат экрану, а не тексту.
  final Set<CodeShortcutType> released;

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) => released.contains(type) ? const [] : super.build(type);
}
