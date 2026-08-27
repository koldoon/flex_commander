import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// Открытый файл: сам текст и то, как его сейчас показывают.
///
/// Экран, а не окно команды: он занимает место панелей, оставляет ряд
/// функциональных кнопок и живёт, пока его не закроют, — а не ровно один
/// запуск команды.
///
/// [ChangeNotifier], потому что показ меняется по ходу дела: `F2` переключает
/// перенос строк, и вид перерисовывается сам.
class ViewerScreen extends ChangeNotifier implements ViewportState, FcSearchable {
  ViewerScreen({
    required FsNode node,
    required String text,
    bool wordWrap = false,
    bool showLineNumbers = false,
    this.onWrapChanged,
    this.onLineNumbersChanged,
  }) : controller = CodeLineEditingController.fromText(text),
       _node = node,
       _wordWrap = wordWrap,
       _showLineNumbers = showLineNumbers;

  /// Общеизвестное имя: к нему привязаны клавиши просмотрщика.
  static const String screenId = 'viewer';

  /// Что показываем: из узла берётся и заголовок, и размер.
  ///
  /// Меняется у наследника: быстрый просмотр показывает то, что под курсором,
  /// и курсор ходит. Во весь экран открывают один файл, и там он постоянен.
  FsNode get node => _node;
  FsNode _node;

  /// Показать другой файл в том же состоянии.
  ///
  /// Не новое состояние на каждый файл: показ, поиск и переносы строк заведены
  /// один раз и переживают смену файла — иначе перебор стрелками сбрасывал бы
  /// их по десять раз в секунду.
  @protected
  void showNode(FsNode node, String text) {
    _node = node;
    controller.text = text;
    notifyListeners();
  }

  /// Содержимое, курсор и выделение. Владеет им экран, а не вид: копирует
  /// команда, а она о виджетах ничего не знает.
  final CodeLineEditingController controller;

  /// Поиск по тексту. Тоже у экрана: искать просит команда, а найденное
  /// подсвечивает вид.
  @override
  late final FcTextFinder finder = FcTextFinder(controller);

  /// Куда сообщить, что перенос переключили, — настройки помнят его между
  /// запусками.
  final void Function(bool wordWrap)? onWrapChanged;

  /// Куда сообщить, что номера строк переключили.
  final void Function(bool showLineNumbers)? onLineNumbersChanged;

  bool _wordWrap;
  bool _showLineNumbers;

  /// Переносить длинные строки. В этом режиме прокрутка только вертикальная:
  /// переносить и одновременно возить по ширине нечего.
  bool get wordWrap => _wordWrap;

  void toggleWordWrap() {
    _wordWrap = !_wordWrap;
    onWrapChanged?.call(_wordWrap);
    notifyListeners();
  }

  /// Показывать номера строк.
  bool get showLineNumbers => _showLineNumbers;

  void toggleLineNumbers() {
    _showLineNumbers = !_showLineNumbers;
    onLineNumbersChanged?.call(_showLineNumbers);
    notifyListeners();
  }

  /// Выделено ли хоть что-нибудь. Спрашивает команда копирования: копировать
  /// нечего — кнопка в ряду останется приглушённой.
  bool get hasSelection => !controller.selection.isCollapsed;

  /// Выделенное мышью или клавишами; пустая строка — не выделено ничего.
  String get selection => controller.selectedText;

  @override
  String get id => screenId;

  /// Фокус нужен: стрелки, страницы и выделение с клавиатуры — дело самого
  /// показа.
  ///
  /// Так было не всегда: пока просмотрщик рисовал строки сам, прокрутка была
  /// командами. Переезд на общий с редактором показ забрал её себе — вместе с
  /// выделением, которое командами и не сделать. Обязанность вернуть фокус при
  /// закрытии лежит на `KeyboardHandler`, см. `docs/screens.md`.
  @override
  bool get takesKeyboard => true;

  @override
  /// Экран закрыли.
  ///
  /// Аренды у просмотрщика нет и не нужно: `TextDocument.read` вычитывает файл
  /// целиком до открытия экрана, и провайдер ему больше не понадобится.
  @override
  void close() => dispose();

  @override
  void dispose() {
    finder.dispose();
    controller.dispose();
    super.dispose();
  }
}
