import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'markdown_viewer_settings.dart';

/// Показ markdown: разобранный документ и то, в каком виде его сейчас смотрят.
class MarkdownViewerScreen extends ChangeNotifier implements ViewerContent {
  MarkdownViewerScreen({
    required this.entry,
    required this.document,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
    this.openWith,
  }) : _formatted = settings.startFormatted;

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'markdown';

  /// Имя экрана — по нему команды узнают своё содержимое.
  static const String screenId = 'markdown';

  @override
  final FileEntry entry;

  @override
  final ViewerPlace place;

  /// Разобранный документ: узлы верхнего уровня и исходный текст.
  final FcMarkdownDocument document;

  final MarkdownViewerSettings settings;
  final void Function() onSettingsChanged;

  /// Чем открыть внешнюю ссылку; null — службы нет, и открывать нечем.
  ///
  /// Службой, а не напрямую: модуль не тащит платформенное, а тест подставляет
  /// своё и проверяет, что именно ушло.
  final SystemOpener? openWith;

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

  /// Исходный текст — им показывают Raw.
  ///
  /// Заводится по первой надобности: открывшему свёрстанный документ буфер
  /// редактора не нужен вовсе.
  CodeLineEditingController get source => _source ??= CodeLineEditingController.fromText(document.source);
  CodeLineEditingController? _source;

  @override
  bool get takesKeyboard => true;

  @override
  void close() => dispose();

  @override
  void dispose() {
    _source?.dispose();
    _source = null;
    super.dispose();
  }
}
