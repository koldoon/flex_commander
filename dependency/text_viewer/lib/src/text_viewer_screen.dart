import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'text_document.dart';

/// Показ текста: сам текст и то, как его сейчас показывают.
///
/// Экран, а не окно команды: он занимает место панелей, оставляет ряд
/// функциональных кнопок и живёт, пока его не закроют, — а не ровно один
/// запуск команды.
///
/// [ChangeNotifier], потому что показ меняется по ходу дела: `F2` переключает
/// перенос строк, `F5` — исходник и отформатированную копию, и вид
/// перерисовывается сам.
class TextViewerScreen extends ChangeNotifier implements ViewerContent, FcSearchable {
  TextViewerScreen({
    required this.entry,
    required String text,
    this.place = ViewerPlace.fullscreen,
    bool wordWrap = false,
    bool showLineNumbers = false,
    this.onWrapChanged,
    this.onLineNumbersChanged,
    List<int>? bytes,
    TextEncoding encoding = TextEncoding.utf8,
    this.memory,
  }) : _raw = text,
       _bytes = bytes,
       _encoding = encoding,
       controller = CodeLineEditingController.fromText(text),
       _wordWrap = wordWrap,
       _showLineNumbers = showLineNumbers;

  /// Общеизвестное имя: по нему поиск находит, чей текст искать.
  static const String screenId = 'text';

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'text';

  /// Под каким ключом выбранная кодировка лежит в памяти показа
  /// (`docs/spec/text-encodings.md`, §4).
  static const String encodingKey = 'text.encoding';

  /// Что показываем: из узла берётся и заголовок, и размер.
  @override
  @override
  final FileEntry entry;

  /// Где показываем: во весь экран или в области панели.
  ///
  /// Приходит при открытии и не меняется. Спросить потом неоткуда: в быстром
  /// просмотре состояние стоит не в области, а внутри хозяина.
  @override
  final ViewerPlace place;

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

  /// Текст файла, как он прочитан. Меняет его только другая кодировка: показ
  /// не умеет писать, а отформатированное — копия (`docs/spec/formatters.md`,
  /// §4).
  String _raw;

  /// Байты файла: другая кодировка перечитывает их, а не показанный текст —
  /// тот уже испорчен неверной. null — байтов нет, и выбирать нечего.
  final List<int>? _bytes;

  /// Память хозяина быстрого просмотра: выбранная руками кодировка помнится,
  /// пока он открыт. null — открыт во весь экран.
  final ViewerMemory? memory;

  /// В какой кодировке прочитан текст.
  TextEncoding get encoding => _encoding;
  TextEncoding _encoding;

  /// Можно ли выбрать другую кодировку.
  bool get canChangeEncoding => _bytes != null;

  /// Перечитать байты в другой кодировке (`docs/spec/text-encodings.md`, §4).
  ///
  /// Отформатированная копия выбрасывается: она считалась по прежнему тексту.
  void setEncoding(TextEncoding encoding) {
    final bytes = _bytes;
    if (bytes == null || encoding == _encoding) {
      return;
    }
    _encoding = encoding;
    memory?.write(entry, encodingKey, encoding);
    _raw = TextDocument.parse(EncodedText.read(bytes, as: encoding)!.text).text;
    _formatted = null;
    _showsFormatted = false;
    _show(_raw);
  }

  /// Отформатированная копия, если её уже считали. Считается один раз: вернуться
  /// к ней вторым нажатием ничего не стоит.
  String? _formatted;

  bool _showsFormatted = false;
  bool _wordWrap;
  bool _showLineNumbers;

  /// Исходный текст — им форматируют и по нему называют место сбоя.
  String get raw => _raw;

  /// Показана ли сейчас отформатированная копия.
  bool get formatted => _showsFormatted;

  /// С какой строки открыть текст; null — с начала.
  ///
  /// Меняется при переключении вида: место чтения переносится **долей** от
  /// длины. Строка в двух видах означает разное — одна строка машинного json
  /// разворачивается в сотню (`docs/spec/formatters.md`, §4).
  int? get startLine => _startLine;
  int? _startLine;

  /// Сверху видно другую строку — говорит вид. Отсюда берётся доля, по которой
  /// место чтения переезжает при переключении.
  void noteTopLine(int line) => _topLine = line;
  int _topLine = 0;

  /// Показать отформатированную копию.
  ///
  /// Форматирует [format] — форматтер из реестра; исключение разбора уходит
  /// наружу, и на экране остаётся исходник: пустой экран не объясняет ничего.
  void showFormatted(String Function(String text) format) {
    if (_showsFormatted) {
      return;
    }
    // Порядок важен: считаем **до** того, как объявить копию показанной, —
    // иначе отказ разбора оставил бы показ в состоянии, которого нет.
    final text = _formatted ??= format(_raw);
    _showsFormatted = true;
    _show(text);
  }

  /// Вернуться к исходнику.
  void showRaw() {
    if (!_showsFormatted) {
      return;
    }
    _showsFormatted = false;
    _show(_raw);
  }

  /// Положить в показ другой текст, перенеся место чтения долей от длины.
  ///
  /// Текст меняется **в том же буфере**: поиск после этого ищет по показанному
  /// сам, и второго буфера, как в markdown, заводить не нужно — там два вида
  /// были разной природы, а здесь оба текст.
  void _show(String text) {
    final was = controller.lineCount;
    final part = was <= 1 ? 0.0 : _topLine / was;
    // Запись через контроллер кладёт правку в его историю, но отмены в показе
    // нет: `Cmd-Z` — правка, а поле открыто для чтения и правок не принимает.
    controller.text = text;
    final lines = controller.lineCount;
    _startLine = (part * lines).round().clamp(0, lines - 1);
    notifyListeners();
  }

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
