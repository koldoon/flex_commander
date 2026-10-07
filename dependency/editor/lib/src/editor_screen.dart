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
       _encoding = file.encoding,
       _bom = file.bom,
       _source = file.source,
       _saveAs = file.encoding,
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

  LineBreak _lineBreak;

  /// В какой кодировке файл записан (`docs/spec/text-encodings.md`, §5).
  TextEncoding get encoding => _encoding;
  TextEncoding _encoding;

  /// Была ли метка порядка байтов — запись вернёт её.
  bool get bom => _bom;
  bool _bom;

  /// Байты файла, как они лежат на диске: другая кодировка перечитывает их.
  List<int> _source;

  /// В чём сохранять — выбирают в окне сохранения: исходная кодировка или
  /// UTF-8 (§5). Вопрос задаётся только про файл не в юникоде.
  TextEncoding get saveAs => _saveAs;
  TextEncoding _saveAs;

  set saveAs(TextEncoding value) {
    if (value == _saveAs) {
      return;
    }
    _saveAs = value;
    notifyListeners();
  }

  /// Спрашивать ли при сохранении, в чём писать.
  bool get asksEncoding => !_encoding.isUnicode;

  /// Первый знак, который не поместится в [saveAs]; null — помещается всё.
  ({String char, int line})? get unsavable {
    final text = controller.text;
    final at = saveAs.unencodable(text);
    if (at == null) {
      return null;
    }
    // Знак вне основной плоскости — два кода, и показать надо оба.
    final unit = text.codeUnitAt(at);
    final wide = unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length;
    return (char: text.substring(at, wide ? at + 2 : at + 1), line: lineOfIndex(text, at));
  }

  /// Метка в записи: у UTF-8, в который перевели, её нет.
  bool get bomToSave => saveAs == _encoding && _bom;

  /// Перечитать файл в другой кодировке (§4). false — в ней он строго не
  /// читается, и текст не тронут. Правки при этом пропали бы, поэтому с
  /// несохранённым не зовут.
  bool reread(TextEncoding encoding) {
    if (encoding == _encoding) {
      return true;
    }
    final file = TextFile.decode(_source, as: encoding);
    if (file == null) {
      return false;
    }
    _encoding = encoding;
    _bom = file.bom;
    _saveAs = encoding;
    _lineBreak = file.lineBreak;
    _saved = file.text;
    controller.text = file.text;
    _modified = false;
    notifyListeners();
    return true;
  }

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

  /// Отформатировать документ на месте.
  ///
  /// `true` — текст изменился; `false` — он уже был таким, и документ не тронут:
  /// лишняя правка пометила бы файл несохранённым на пустом месте, а отмена
  /// потратилась бы на шаг, который ничего не менял.
  ///
  /// Замена идёт **через контроллер**: он кладёт её в свою историю
  /// (`runRevocableOp`), значит обычная отмена возвращает как было, и своей
  /// отмены заводить не нужно (`docs/spec/formatters.md`, §5).
  ///
  /// Не разобралось — [format] бросает, и документ не меняется вовсе: подменить
  /// кривой документ на «как получилось» значило бы потерять то, что человек
  /// писал.
  ///
  /// Курсор после замены встаёт в начало. Место сохранить нечем: строка после
  /// перестройки означает не то же, что до неё, а курсор — это то, куда будут
  /// печатать; наугад его ставить нельзя.
  bool format(String Function(String text) format) {
    final text = controller.text;
    final formatted = format(text);
    if (formatted == text) {
      return false;
    }

    controller.text = formatted;

    return true;
  }

  /// Записанное стало сохранённым — в той кодировке, в которой записали.
  void markSaved() {
    final bom = bomToSave;
    _encoding = saveAs;
    _bom = bom;
    _source = EncodedText(textToSave, _encoding, bom: _bom).bytes;
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
