import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import 'syntax/syntax_highlighter.dart';
import 'text_document.dart';
import 'viewer_view.dart';

/// Как раздобыть подсветку под цвета текущего оформления.
typedef HighlighterFactory = SyntaxHighlighter Function(FcColors colors);

/// Куда двигать показ.
enum ScrollStep { lineUp, lineDown, pageUp, pageDown, toStart, toEnd, columnLeft, columnRight }

/// Кто умеет двигать показ: сам вид, когда он на экране.
typedef Scroller = void Function(ScrollStep step);

/// Открытый файл: сам текст и то, как его сейчас показывают.
///
/// Экран, а не окно команды: он занимает место панелей, оставляет ряд
/// функциональных кнопок и живёт, пока его не закроют, — а не ровно один
/// запуск команды.
///
/// [ChangeNotifier], потому что показ меняется по ходу дела: `F2` переключает
/// перенос строк, и вид перерисовывается сам.
class ViewerScreen extends ChangeNotifier implements Screen {
  ViewerScreen({
    required this.node,
    required this.document,
    required this.highlighterFor,
    bool wordWrap = false,
    this.onWrapChanged,
  }) : _wordWrap = wordWrap;

  /// Общеизвестное имя: к нему привязаны клавиши просмотрщика.
  static const String screenId = 'viewer';

  /// Что показываем: из узла берётся и заголовок, и размер.
  final FsNode node;

  final TextDocument document;

  final HighlighterFactory highlighterFor;

  /// Куда сообщить, что перенос переключили, — настройки помнят его между
  /// запусками.
  final void Function(bool wordWrap)? onWrapChanged;

  bool _wordWrap;

  /// Переносить длинные строки. В этом режиме прокрутка только вертикальная:
  /// переносить и одновременно возить по ширине нечего.
  bool get wordWrap => _wordWrap;

  void toggleWordWrap() {
    _wordWrap = !_wordWrap;
    onWrapChanged?.call(_wordWrap);
    notifyListeners();
  }

  @override
  String get id => screenId;

  /// Фокус просмотрщику не нужен.
  ///
  /// Прокрутка у него — такие же команды, как и всё остальное: клавиша
  /// принадлежит экрану, ряд кнопок показывает то, что она сделает, а
  /// переназначить её можно будет из настроек. Отдать прокрутку `Scrollable`
  /// значило бы завести вторую, невидимую систему клавиш — и заодно
  /// разбираться, кому возвращать фокус, когда экран закроется.
  @override
  bool get takesFocus => false;

  Scroller? _scroller;

  /// Вид сообщает о себе, когда появляется на экране, и отзывается, когда
  /// уходит: контроллеры прокрутки принадлежат ему, и он же их закрывает.
  void attachScroller(Scroller scroller) => _scroller = scroller;

  void detachScroller(Scroller scroller) {
    if (identical(_scroller, scroller)) {
      _scroller = null;
    }
  }

  /// Двигает показ. Пока вида нет, двигать нечего — это не ошибка.
  void scroll(ScrollStep step) => _scroller?.call(step);

  @override
  Widget build(BuildContext context) => ViewerView(screen: this);
}
