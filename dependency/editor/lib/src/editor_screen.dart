import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'editor_view.dart';
import 'text_file.dart';

/// Файл, открытый на правку.
///
/// Экран, а не окно команды: он занимает место панелей, оставляет ряд
/// функциональных кнопок и живёт, пока его не закроют.
///
/// В отличие от просмотрщика **берёт фокус себе**: печатать надо в текст, а не
/// в команды. Обязанность вернуть фокус при закрытии лежит на
/// `KeyboardHandler` — см. `docs/screens.md`.
class EditorScreen extends ChangeNotifier implements Screen {
  EditorScreen({required this.node, required TextFile file, required bool wordWrap, this.onWrapChanged})
    : _lineBreak = file.lineBreak,
      _saved = file.text,
      _wordWrap = wordWrap,
      controller = CodeLineEditingController.fromText(file.text) {
    controller.addListener(_onTextChanged);
  }

  static const String screenId = 'editor';

  /// Что правим: из узла берётся и заголовок, и куда сохранять.
  final FsNode node;

  /// Содержимое и курсор. Владеет им экран: сохранять просит команда, а она о
  /// виджетах ничего не знает.
  final CodeLineEditingController controller;

  final void Function(bool wordWrap)? onWrapChanged;

  final LineBreak _lineBreak;

  /// Текст, каким он лежит в файле. По нему видно, есть ли несохранённое.
  String _saved;

  bool _wordWrap;
  bool _modified = false;

  bool get wordWrap => _wordWrap;

  /// Есть ли изменения, которых нет в файле.
  bool get modified => _modified;

  /// Содержимое в том виде, в каком его надо записать: с исходными переводами
  /// строк, а не с теми, к которым их привёл разбор.
  String get textToSave {
    final text = controller.text;
    return _lineBreak == LineBreak.lf ? text : text.replaceAll('\n', _lineBreak.text);
  }

  void toggleWordWrap() {
    _wordWrap = !_wordWrap;
    onWrapChanged?.call(_wordWrap);
    notifyListeners();
  }

  /// Записанное стало сохранённым.
  void markSaved() {
    _saved = controller.text;
    _modified = false;
    notifyListeners();
  }

  void _onTextChanged() {
    final changed = controller.text != _saved;
    if (changed != _modified) {
      _modified = changed;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onTextChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  String get id => screenId;

  /// Фокус нужен: иначе некуда печатать.
  @override
  bool get takesFocus => true;

  @override
  Widget build(BuildContext context) => EditorView(screen: this);
}
