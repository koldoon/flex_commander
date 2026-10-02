import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'pdf_document.dart';

/// Поиск по страницам: ищет система, подсвечивает показ
/// (`docs/spec/pdf-viewer.md`, §9).
///
/// Окно поиска то же, что у текста: оно спрашивает [FcFinder] и не знает,
/// кто ищет. Выражений система не умеет — и флажка для них в окне нет.
class PdfFinder extends ChangeNotifier implements FcFinder {
  PdfFinder(this.document, {required this.reveal});

  final PdfDocument document;

  /// Подвести показ к найденному.
  final void Function(PdfMatch match) reveal;

  List<PdfMatch> _matches = const [];
  int _index = 0;

  /// Найденное — показ подсвечивает его на страницах.
  List<PdfMatch> get matches => _matches;

  /// Текущее; null — не искали или не нашли.
  PdfMatch? get current => _matches.isEmpty ? null : _matches[_index];

  @override
  String get pattern => _pattern;
  String _pattern = '';

  @override
  bool get caseSensitive => _caseSensitive;
  bool _caseSensitive = false;

  @override
  bool get regex => false;

  @override
  bool get supportsRegex => false;

  @override
  int get matchCount => _matches.length;

  @override
  int get currentIndex => _matches.isEmpty ? 0 : _index + 1;

  /// Поколение поиска: догнавший ответ прежней строки не показывается.
  int _generation = 0;

  @override
  Future<int> search(String text, {bool caseSensitive = false, bool regex = false}) async {
    _pattern = text;
    _caseSensitive = caseSensitive;
    final generation = ++_generation;
    if (text.isEmpty) {
      clear();
      return 0;
    }
    final found = await document.handle.find(text, caseSensitive: caseSensitive);
    if (generation != _generation) {
      return matchCount;
    }
    _matches = found;
    _index = 0;
    notifyListeners();
    _revealCurrent();
    return matchCount;
  }

  @override
  bool next() => _step(1);

  @override
  bool previous() => _step(-1);

  bool _step(int delta) {
    if (_matches.isEmpty) {
      return false;
    }
    _index = (_index + delta) % _matches.length;
    notifyListeners();
    _revealCurrent();
    return true;
  }

  @override
  void clear() {
    if (_matches.isEmpty) {
      return;
    }
    _matches = const [];
    _index = 0;
    notifyListeners();
  }

  void _revealCurrent() {
    final match = current;
    if (match != null) {
      reveal(match);
    }
  }
}
