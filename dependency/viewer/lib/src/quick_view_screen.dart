import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';

import 'text_document.dart';
import 'viewer_screen.dart';
import 'viewer_settings.dart';

/// Быстрый просмотр: содержимое того, что под курсором соседней панели.
///
/// Наследник просмотрщика, а не свой экран, и это не экономия строк: клавиши
/// объявлены `KeyBinding.inState<ViewerScreen>`, а условие там — `state is S`.
/// Значит перенос строк, номера строк, поиск и копирование достаются быстрому
/// просмотру **тем же самым объявлением**, и разойтись им негде.
///
/// Живёт наложением на область панели: под ним цела и панель, и её курсор, и
/// аренда источника. Сама панель о просмотре не знает — это он слушает её, а
/// не она его.
class QuickViewScreen extends ViewerScreen {
  QuickViewScreen({
    required this.panel,
    required this.settings,
    required this.onSettingsChanged,
    this.delay = defaultDelay,
  }) : super(
         node: panel.currentNode ?? _placeOf(panel),
         text: '',
         wordWrap: settings.wordWrap,
         showLineNumbers: settings.showLineNumbers,
       ) {
    panel.addListener(_onPanelChanged);
    _onPanelChanged(immediately: true);
  }

  /// Пауза между шагом курсора и чтением файла.
  ///
  /// **Ожидание тишины, а не ограничение частоты.** `Throttle` из API
  /// пропускает первое событие сразу и придерживает следующие — он про то,
  /// чтобы не перерисовывать чаще, чем видит глаз. Здесь нужно обратное: пока
  /// стрелка едет вниз по списку, читать не надо ничего, а прочитать надо то,
  /// на чём она остановилась.
  static const Duration defaultDelay = Duration(milliseconds: 150);

  /// Панель, за курсором которой идёт просмотр.
  final Panel panel;

  final ViewerSettings settings;
  final void Function() onSettingsChanged;

  final Duration delay;

  /// Что показать вместо текста: каталог, слишком большой файл, ошибка чтения.
  /// null — показан файл.
  String? get notice => _notice;
  String? _notice;

  /// Узел, который сейчас показан или читается. Отличается от `panel.currentNode`
  /// ровно на время паузы и чтения.
  FsNode? _target;

  Timer? _waiting;

  /// Поколение чтения: пришёл ответ не того поколения — курсор ушёл дальше, и
  /// показывать его уже нельзя.
  int _generation = 0;

  bool _disposed = false;

  /// Чем назваться, когда под курсором ничего нет: сам каталог панели.
  ///
  /// Узел просмотрщику нужен всегда — из него берётся заголовок, — а в пустом
  /// каталоге курсору стоять не на чем. Поддельного узла ради этого заводить
  /// не приходится: каталог у панели есть, и он же честно отвечает на вопрос
  /// «где мы».
  static FsNode _placeOf(Panel panel) =>
      panel.directory ?? DirectoryNode(provider: panel.provider, name: panel.provider.homePath);

  void _onPanelChanged({bool immediately = false}) {
    final node = panel.currentNode;
    if (identical(node, _target)) {
      // Панель сообщает и о своих делах — о чтении каталога, о пометке. Файл
      // при этом тот же, и перечитывать его незачем.
      return;
    }
    _target = node;
    _waiting?.cancel();
    _generation++;

    if (immediately) {
      unawaited(_show(node, _generation));
      return;
    }
    _waiting = Timer(delay, () => unawaited(_show(node, _generation)));
  }

  Future<void> _show(FsNode? node, int generation) async {
    if (node == null) {
      _say('Nothing to show', node);
      return;
    }
    if (node is ParentDirNode) {
      _say('Parent directory', node);
      return;
    }
    if (node is DirectoryNode) {
      // Сводку по каталогу — сколько в нём файлов и байт — здесь не считаем:
      // это обход дерева на каждый шаг курсора, и для него есть своя команда
      // (`Alt-Shift-Enter`).
      _say('Directory', node);
      return;
    }

    final source = node.provider;
    if (source is! FileContentProvider) {
      // Так выглядят результаты поиска: узлы есть, байтов за ними нет.
      _say('No content', node);
      return;
    }
    if (node.size > settings.maxFileSize) {
      // Теми же словами, что говорит `F3`, но **в панели**, а не тостом: тост
      // выскакивал бы на каждом шаге курсора и мигал бы всю дорогу.
      _say('File is too large: ${formatBytesLong(node.size)}, limit is ${formatSize(settings.maxFileSize)}', node);
      return;
    }

    try {
      final bytes = <int>[];
      await for (final chunk in await (source as FileContentProvider).openRead(node)) {
        // Курсор ушёл дальше — дочитывать незачем: `TextDocument.read` дочитал
        // бы до конца, ни у кого не спросив, а здесь файл меняется чаще, чем
        // читается.
        if (generation != _generation || _disposed) {
          return;
        }
        bytes.addAll(chunk);
      }
      if (generation != _generation || _disposed) {
        return;
      }
      _notice = null;
      showNode(node, TextDocument.parse(utf8.decode(bytes, allowMalformed: true)).text);
    } on Object catch (error) {
      if (generation == _generation && !_disposed) {
        _say(error is FsError ? error.message : '$error', node);
      }
    }
  }

  /// Показать словами вместо текста.
  void _say(String message, FsNode? node) {
    if (_disposed) {
      return;
    }
    _notice = message;
    showNode(node ?? _placeOf(panel), '');
  }

  @override
  void dispose() {
    _disposed = true;
    _waiting?.cancel();
    panel.removeListener(_onPanelChanged);
    super.dispose();
  }
}
