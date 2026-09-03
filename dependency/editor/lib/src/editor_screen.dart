import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'text_file.dart';

/// Файл, открытый на правку.
///
/// Экран, а не окно команды: он занимает место панелей, оставляет ряд
/// функциональных кнопок и живёт, пока его не закроют.
///
/// В отличие от просмотрщика **берёт фокус себе**: печатать надо в текст, а не
/// в команды. Обязанность вернуть фокус при закрытии лежит на
/// `KeyboardHandler` — см. `docs/screens.md`.
class EditorScreen extends ChangeNotifier implements ViewportState, FcSearchable {
  EditorScreen({
    required this.entry,
    required TextFile file,
    required bool wordWrap,
    bool showLineNumbers = true,
    this.readOnly = false,
    this.onWrapChanged,
    this.onLineNumbersChanged,
  }) : _lineBreak = file.lineBreak,
       _saved = file.text,
       _wordWrap = wordWrap,
       _showLineNumbers = showLineNumbers,
       controller = CodeLineEditingController.fromText(file.text) {
    controller.addListener(_onTextChanged);
  }

  static const String screenId = 'editor';

  /// Что правим: из узла берётся и заголовок, и куда сохранять.
  /// Что правят — строкой списка: узлы живут в ядре.
  final FileEntry entry;

  /// Файл открыт только на чтение: писать в него не пустили, а показать и
  /// поискать по нему всё равно надо.
  ///
  /// Правка выключена (`FcTextView.readOnly`), `editor.save` невыполнима, а в
  /// заголовке вместо знака несохранённого стоит `read-only`. Спорить им не о
  /// чем: в файле, который нельзя записать, несохранённому взяться неоткуда.
  final bool readOnly;

  /// Содержимое и курсор. Владеет им экран: сохранять просит команда, а она о
  /// виджетах ничего не знает.
  final CodeLineEditingController controller;

  /// Поиск по тексту — такой же, как в просмотрщике: показ у них общий.
  @override
  late final FcTextFinder finder = FcTextFinder(controller);

  final void Function(bool wordWrap)? onWrapChanged;

  /// Куда сообщить, что номера строк переключили.
  final void Function(bool showLineNumbers)? onLineNumbersChanged;

  final LineBreak _lineBreak;

  /// Текст, каким он лежит в файле. По нему видно, есть ли несохранённое.
  String _saved;

  bool _wordWrap;
  bool _showLineNumbers;
  bool _modified = false;

  bool get wordWrap => _wordWrap;

  /// Показывать номера строк.
  bool get showLineNumbers => _showLineNumbers;

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

  void toggleLineNumbers() {
    _showLineNumbers = !_showLineNumbers;
    onLineNumbersChanged?.call(_showLineNumbers);
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
  /// Экран закрыли: источник больше не нужен.
  @override
  void close() {
    // Отпускания не ждут: дальше экран не используется, а закрытие архива —
    // уборка за ним.
    dispose();
  }

  @override
  void dispose() {
    finder.dispose();
    controller.removeListener(_onTextChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  String get id => screenId;

  /// Фокус нужен: иначе некуда печатать.
  @override
  bool get takesKeyboard => true;
}
