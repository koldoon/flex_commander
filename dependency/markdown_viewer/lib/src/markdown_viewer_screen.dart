import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'markdown_viewer_settings.dart';

/// Показ markdown: разобранный документ и то, в каком виде его сейчас смотрят.
class MarkdownViewerScreen extends ChangeNotifier implements ViewerContent, FcSearchable {
  MarkdownViewerScreen({
    required this.entry,
    required this.document,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
    this.openWith,
    this.resolveImage,
  }) : _formatted = settings.startFormatted;

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'markdown';

  /// Имя экрана — по нему команды поиска узнают своё содержимое.
  static const String screenId = 'markdown';

  @override
  final FileEntry entry;

  @override
  final ViewerPlace place;

  /// Разобранный документ: узлы верхнего уровня, исходник и проекция видимого.
  final FcMarkdownDocument document;

  final MarkdownViewerSettings settings;
  final void Function() onSettingsChanged;

  /// Чем открыть внешнюю ссылку; null — службы нет, и открывать нечем.
  ///
  /// Службой, а не напрямую: модуль не тащит платформенное, а тест подставляет
  /// своё и проверяет, что именно ушло.
  final SystemOpener? openWith;

  /// Чем прочесть картинку из документа; null — читать нечем.
  final FcImageResolver? resolveImage;

  @override
  String get id => screenId;

  /// Показывать свёрстанным; иначе — исходником.
  bool get formatted => _formatted;
  bool _formatted;

  /// Переключить вид — и запомнить выбор.
  ///
  /// Запоминается именно выбор, а не состояние одного файла: человек, которому
  /// привычнее исходник, не должен нажимать `F5` на каждом документе.
  void toggleFormat() {
    _formatted = !_formatted;
    settings.startFormatted = _formatted;
    onSettingsChanged();
    notifyListeners();
  }

  /// Исходный текст — им показывают Raw и в нём же ищут в этом виде.
  ///
  /// Заводится по первой надобности: открывшему свёрстанный документ буфер
  /// редактора не нужен вовсе.
  CodeLineEditingController get source => _source ??= CodeLineEditingController.fromText(document.source);
  CodeLineEditingController? _source;

  /// Видимый текст — по нему ищут в свёрстанном виде.
  ///
  /// На экране этого поля нет: оно существует ради [FcTextFinder], который
  /// построен на буфере редактора и другого текста не знает. Найденное
  /// превращается в место на экране картой «строка → блок»
  /// (`docs/spec/markdown-viewer.md`, §7).
  CodeLineEditingController get shown => _shown ??= CodeLineEditingController.fromText(document.plainText);
  CodeLineEditingController? _shown;

  /// Поиск того вида, который показан сейчас.
  ///
  /// Ищут по тому, что видно: в свёрстанном — по видимому тексту, в исходнике —
  /// по разметке. Иначе человек находил бы звёздочки, которых на экране нет.
  @override
  FcTextFinder get finder => _formatted ? _shownFinder : _sourceFinder;

  FcTextFinder get _sourceFinder => _sourceFind ??= FcTextFinder(source);
  FcTextFinder? _sourceFind;

  FcTextFinder get _shownFinder => _shownFind ??= FcTextFinder(shown)..findController.addListener(_followMatch);
  FcTextFinder? _shownFind;

  /// Блок, в котором стоит текущее совпадение; null — не ищут или не нашлось.
  int? get activeBlock => _activeBlock;
  int? _activeBlock;

  /// Совпадение переехало — перевести его в номер блока.
  void _followMatch() {
    final match = _shownFind?.findController.currentMatchSelection;
    final line = match?.start.index;
    final blocks = document.blockOfLine;

    final block = line == null || line < 0 || line >= blocks.length ? null : blocks[line];
    if (block == _activeBlock) {
      return;
    }
    _activeBlock = block;
    notifyListeners();
  }

  @override
  bool get takesKeyboard => true;

  @override
  void close() => dispose();

  @override
  void dispose() {
    _shownFind?.findController.removeListener(_followMatch);
    _sourceFind?.dispose();
    _shownFind?.dispose();
    _source?.dispose();
    _shown?.dispose();
    _sourceFind = null;
    _shownFind = null;
    _source = null;
    _shown = null;
    super.dispose();
  }
}
