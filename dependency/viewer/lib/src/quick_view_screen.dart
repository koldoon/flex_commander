import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'viewer_choice.dart';

/// Быстрый просмотр: содержимое того, что под курсором соседней панели.
///
/// **Хозяин, а не просмотрщик.** Внутри стоит показ, выбранный реестром, и
/// меняется он вместе с курсором: рядом с `readme.md` лежит `logo.png`, и
/// меняется не файл, а сам просмотрщик. Наследованием, как было до реестра,
/// этого не сделать.
///
/// За хозяином остаётся всё, что не про содержимое: подписка на панель, пауза
/// перед чтением, отмена начатого и слова вместо показа, когда показывать
/// нечего.
///
/// Живёт наложением на область панели: под ним цела и панель, и её курсор, и
/// аренда источника. Сама панель о просмотре не знает — это он слушает её.
class QuickViewHost extends ChangeNotifier implements ViewportHost {
  QuickViewHost({required this.app, required this.panel, this.delay = defaultDelay}) {
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

  final Application app;

  /// Панель, за курсором которой идёт просмотр.
  final Panel panel;

  final Duration delay;

  /// Что показано внутри; null — показывать нечего.
  @override
  ViewportState? get inner => _inner;
  ViewportState? _inner;

  /// Что сказать вместо показа: каталог, отказ просмотрщика, ошибка чтения.
  /// null — показан файл.
  String? get notice => _notice;
  String? _notice;

  /// Узел, который показан или читается. Отличается от `panel.currentNode`
  /// ровно на время паузы и чтения.
  FileEntry? _target;

  Timer? _waiting;

  /// Поколение чтения: пришёл ответ не того поколения — курсор ушёл дальше.
  int _generation = 0;

  bool _disposed = false;

  /// Фокус хозяину не нужен: его берёт то, что внутри, — и только когда в
  /// показ вошли.
  @override
  bool get takesKeyboard => _inner?.takesKeyboard ?? false;

  void _onPanelChanged({bool immediately = false}) {
    final entry = panel.currentEntry;
    // Строка та же — перечитывать нечего: панель сообщает и о своих делах, о
    // чтении каталога и о пометке. Сравниваются имя и путь: значения между
    // собой ссылкой не сравнить.
    if (entry?.name == _target?.name && entry?.path == _target?.path) {
      return;
    }
    _target = entry;
    _waiting?.cancel();
    _generation++;

    if (immediately) {
      unawaited(_show(entry, _generation));
      return;
    }
    _waiting = Timer(delay, () => unawaited(_show(entry, _generation)));
  }

  Future<void> _show(FileEntry? entry, int generation) async {
    if (entry == null) {
      _say('Nothing to show');
      return;
    }
    if (entry.isParent) {
      // Про «..» сказать нечего: это не объект, а дорога наверх.
      _say('Parent directory');
      return;
    }

    // Пока читаем — говорим об этом сами, своей же строкой. Занять панель
    // здесь нечем: быстрый просмотр её и заменил, панели в этой области нет.
    // А чужую, активную, занимать нельзя — по ней в это время водят курсором,
    // ради чего быстрый просмотр и открывают.
    _say('Reading ${entry.name}…');

    try {
      final content = await openViewer(
        app,
        entry,
        panel.contentOf(entry),
        ViewerPlace.panel,
        siblings: panel.entries,
        contentOf: panel.contentOf,
        // Курсор ушёл дальше — дочитывать незачем: просмотрщик спрашивает об
        // этом сам, по ходу чтения.
        checkpoint: () async {
          if (generation != _generation || _disposed) {
            throw const OperationCanceled();
          }
        },
      );
      if (generation != _generation || _disposed) {
        content.close();
        return;
      }
      _replace(content, notice: null);
    } on OperationCanceled {
      // Ушли дальше по списку — это не ошибка, а обычный ход дела.
    } on ViewerRefused catch (refusal) {
      // Словами в самой панели, а не тостом: тост выскакивал бы на каждом шаге
      // курсора и мигал бы всю дорогу.
      if (generation == _generation) {
        _say(refusal.reason);
      }
    } on Object catch (error) {
      if (generation == _generation) {
        _say(error is FsError ? error.message : '$error');
      }
    }
  }

  /// Показать словами вместо показа.
  void _say(String message) {
    if (_disposed) {
      return;
    }
    _replace(null, notice: message);
  }

  void _replace(ViewportState? content, {required String? notice}) {
    // Прежнее закрывается: показ держит и текст, и поиск, и — у будущих
    // просмотрщиков — распакованную картинку. Забыть его здесь значило бы
    // копить их по одному на каждый шаг курсора.
    _inner?.close();
    _inner = content;
    _notice = notice;
    notifyListeners();
  }

  @override
  void close() => dispose();

  @override
  void dispose() {
    _disposed = true;
    _waiting?.cancel();
    panel.removeListener(_onPanelChanged);
    _inner?.close();
    _inner = null;
    super.dispose();
  }
}
