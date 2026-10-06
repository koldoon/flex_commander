import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'open_viewer.dart';

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
  QuickViewHost({required this.app, required Session panel, required this.source, this.delay = defaultDelay})
    : _panel = panel {
    _panel.addListener(_onPanelChanged);
    app.view.addListener(_onViewChanged);
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

  /// Область, за панелью которой идёт просмотр.
  final ViewportPosition source;

  /// Панель, за курсором которой идёт просмотр, — та, что показана в [source]
  /// **сейчас**.
  ///
  /// Не та, что была при открытии: в ряду сверху меняют набор, и в области
  /// оказывается другая сессия. Держись просмотр за прежнюю — показывал бы её
  /// файл, а ход курсора в новой до него не доходил бы (живой дефект
  /// 6 октября 2026).
  Session get panel => _panel;
  Session _panel;

  /// В области показано другое — перейти на сессию, что теперь там.
  ///
  /// Не панель (просмотрщик во весь экран, поиск поверх) — держимся прежней:
  /// когда это снимут, вернётся она же или другая, и тогда и перейдём.
  void _onViewChanged() {
    if (_disposed) {
      return;
    }
    final shown = app.view.panelAt(source);
    if (shown == null || identical(shown, _panel)) {
      return;
    }
    _panel.removeListener(_onPanelChanged);
    _panel = shown;
    _panel.addListener(_onPanelChanged);
    _onPanelChanged();
  }

  final Duration delay;

  /// Что показано внутри; null — показывать нечего.
  @override
  ViewportState? get inner => _inner;
  ViewportState? _inner;

  /// Что сказать вместо показа: каталог, отказ просмотрщика, ошибка чтения.
  /// null — показан файл.
  String? get notice => _notice;
  String? _notice;

  /// Что читается прямо сейчас поверх уже показанного; null — ничего не ждём.
  ///
  /// **Показанное не гаснет, пока не готово новое.** Пока чтение шло, на месте
  /// картинки появлялось слово «Чтение…» — и при ходьбе стрелками по каталогу
  /// снимков просмотр мигал на каждом шаге. Во весь экран этого не бывает:
  /// там картинка стоит, пока не приедет следующая, — и здесь должно быть так
  /// же (`docs/spec/quick-view.md`).
  ///
  /// Показывать нечего — тогда и держать нечего: первый файл по-прежнему
  /// говорит словами, что его читают.
  String? get loading => _loading;
  String? _loading;

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
      _say(app.strings.tr('Nothing to show'));
      return;
    }
    if (entry.isParent) {
      // Про «..» сказать нечего: это не объект, а дорога наверх.
      _say(app.strings.tr('Parent directory'));
      return;
    }

    // Пока читаем — говорим об этом сами, своей же строкой. Занять панель
    // здесь нечем: быстрый просмотр её и заменил, панели в этой области нет.
    // А чужую, активную, занимать нельзя — по ней в это время водят курсором,
    // ради чего быстрый просмотр и открывают.
    //
    // Но если показ уже стоит, он и остаётся: мигать на каждом шаге курсора
    // хуже, чем подождать молча. О чтении в этом случае говорит подсказка.
    _reading(app.strings.tr('Reading {name}…', args: {'name': entry.name}));

    try {
      final content = await openViewer(
        app,
        entry,
        panel.contentOf(entry),
        ViewerPlace.panel,
        siblings: panel.entries,
        sourceOf: panel.sourceOf,
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

  /// Сказать, что идёт чтение, — не гася того, что уже показано.
  void _reading(String message) {
    if (_disposed) {
      return;
    }
    if (_inner == null) {
      _say(message);
      return;
    }
    _loading = message;
    notifyListeners();
  }

  void _replace(ViewportState? content, {required String? notice}) {
    _loading = null;
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
    _panel.removeListener(_onPanelChanged);
    app.view.removeListener(_onViewChanged);
    _inner?.close();
    _inner = null;
    super.dispose();
  }
}
