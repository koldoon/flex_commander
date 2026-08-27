import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';

import 'app_controller.dart';

/// Рабочая область приложения — реализация [ApplicationView].
///
/// У каждой области стопка состояний. Внизу — то, что в области стоит; сверху —
/// наложения. Замена меняет дно и прежнее закрывает; наложение кладётся поверх,
/// и под ним всё живо — каталог, курсор, аренда.
///
/// `fullscreen` отличается только тем, что его стопка может быть пустой: сняли
/// последний слой — видно панели.
class AppViewController extends ChangeNotifier implements ApplicationView {
  AppViewController(this._app) {
    _stacks[ViewportPosition.left] = [_app.left];
    _stacks[ViewportPosition.right] = [_app.right];
  }

  final AppController _app;

  final Map<ViewportPosition, List<ViewportState>> _stacks = {
    for (final position in ViewportPosition.values) position: <ViewportState>[],
  };

  /// Верхнее состояние, если оно умеет сообщать о себе.
  ///
  /// Иначе ряд функциональных кнопок замирает: он подписан на область, а
  /// доступность его команд зависит от того, что происходит внутри, — есть ли
  /// в редакторе несохранённое, выделено ли что-нибудь в просмотрщике.
  Listenable? _watched;

  /// Стопка области снизу вверх — для тестов и отладки.
  List<ViewportState> stackAt(ViewportPosition position) => List.unmodifiable(_stacks[position]!);

  /// Пустой может быть только стопка `fullscreen`: панель убрать нельзя,
  /// её можно лишь заменить.
  bool _canEmpty(ViewportPosition position) => position == ViewportPosition.fullscreen;

  @override
  ViewportState? contentAt(ViewportPosition position) {
    final stack = _stacks[position]!;
    return stack.isEmpty ? null : stack.last;
  }

  @override
  Panel? panelAt(ViewportPosition position) {
    final content = contentAt(position);
    return content is Panel ? content : null;
  }

  @override
  void setViewportContent(ViewportPosition position, ViewportState state) {
    final stack = _stacks[position]!;
    // Наложения уходят вместе с прежним дном: они лежали поверх того, чего
    // больше нет.
    final leaving = [...stack];
    stack
      ..clear()
      ..add(state);
    if (_focused == position) {
      _focused = null;
    }
    _closeAll(leaving);
    _afterChange();
  }

  /// Есть ли над дном хоть одно наложение.
  ///
  /// У панельной области дно — сама панель, и её наложением не заменить: панель
  /// убирают не так. У `fullscreen` дна нет вовсе, и заменять можно всё.
  bool _hasOverlay(ViewportPosition position) => _stacks[position]!.length > (_canEmpty(position) ? 0 : 1);

  @override
  void pushViewportContent(ViewportPosition position, ViewportState state) {
    final stack = _stacks[position]!;
    // Тот же вид второй раз — это замена верхнего слоя, а не второй слой над
    // первым: два просмотрщика друг над другом не стопка, а недосмотр.
    //
    // Условие про **наложение над дном**, а не про то, бывает ли область
    // пустой: раньше здесь стояло второе, и в панельной области настоящее
    // наложение вторым слоем всё-таки ложилось.
    if (_hasOverlay(position) && stack.last.runtimeType == state.runtimeType) {
      final leaving = stack.removeLast();
      leaving.close();
    }
    stack.add(state);
    _afterChange();
  }

  @override
  void popViewportContent(ViewportPosition position) {
    final stack = _stacks[position]!;
    if (!_hasOverlay(position)) {
      // Снимать нечего: на дне стоит панель, и убрать её нельзя — только
      // заменить. Это не ошибка: команда закрытия может прийти и после того,
      // как содержимое уже ушло.
      return;
    }
    stack.removeLast().close();
    // Ввод был в наложении — теперь его нет, и держать за ним область нельзя:
    // иначе активной считалась бы та, где снова стоит обычная панель, а
    // рисовалась бы активной другая.
    if (_focused == position) {
      _focused = null;
    }
    _afterChange();
  }

  /// Область, взявшая ввод себе, — из тех, у кого своего признака активности
  /// нет. Сегодня это командная строка; null — ввод там, где он и так был.
  ViewportPosition? _focused;

  /// Область, которой принадлежит ввод.
  ///
  /// Почти выводится: полноэкранное по определению забирает ввод себе, а в
  /// остальное время он у той панели, которая активна. Между ними — область,
  /// **явно** его взявшая: командная строка. Хранить её приходится, потому что
  /// вывести неоткуда — стоит она внизу всегда, а ввод у неё только по просьбе.
  ///
  /// Порядок именно такой. Полноэкранное перекрывает и строку: после `Enter`
  /// ввод принадлежит терминалу, а не строке под ним. Свернули терминал — ввод
  /// вернулся строке, потому что [_focused] никуда не делся.
  @override
  ViewportPosition get activeArea {
    if (_stacks[ViewportPosition.fullscreen]!.isNotEmpty) {
      return ViewportPosition.fullscreen;
    }
    final focused = _focused;
    // Содержимое могли убрать вместе с модулем: ввод тогда возвращается туда,
    // где ему и место.
    if (focused != null && contentAt(focused) != null) {
      return focused;
    }
    return sourceArea;
  }

  @override
  ViewportPosition? positionOf(ViewportState content) {
    for (final entry in _stacks.entries) {
      if (entry.value.any((state) => _holds(state, content))) {
        return entry.key;
      }
    }
    return null;
  }

  /// Стоит ли [content] в [outer] — им самим или внутри него.
  ///
  /// Хозяин показывает не себя: в области стоит быстрый просмотр, а видно
  /// текст внутри него. Спрашивают оба — и хозяин, и тот, кто внутри, — и
  /// ответ им положен одинаковый.
  static bool _holds(ViewportState outer, ViewportState content) {
    for (ViewportState? state = outer; state != null; state = state is ViewportHost ? state.inner : null) {
      if (identical(state, content)) {
        return true;
      }
    }
    return false;
  }

  @override
  bool takesKeys(ViewportState content) {
    final active = activeArea;
    final shown = contentAt(active);
    if (shown != null && _holds(shown, content)) {
      return true;
    }
    // Командная строка забирает ввод, но клавиши, которых у однострочного поля
    // нет, оставляет панели — `F1`…`F12` и стрелки. Значит панель ими и
    // распоряжается: курсор в ней ходит, и приглушать её нечестно.
    final source = contentAt(sourceArea);
    return active == ViewportPosition.bottom && source != null && _holds(source, content);
  }

  @override
  ViewportPosition get sourceArea => _app.left.active ? ViewportPosition.left : ViewportPosition.right;

  /// Отпускает ввод, взятый областью без своей активности. true — он был у неё.
  ///
  /// Зовёт приложение при переходе к панели: путей туда много — щелчок мышью,
  /// `Tab`, команда, — и все они идут через `activate`, а не через [setFocus].
  bool releaseFocus() {
    if (_focused == null) {
      return false;
    }
    _focused = null;
    notifyListeners();
    return true;
  }

  @override
  void setFocus(ViewportPosition position) {
    final panel = panelAt(position);
    if (panel != null) {
      // Ввод вернулся панели: отпускает его `activate` — он же и уведомит.
      _app.activate(panel);
      return;
    }
    // У областей без панели своего состояния активности нет: `fullscreen`
    // активен, пока в нём что-то лежит, и снимать это не дело фокуса.
    _focused = position == ViewportPosition.fullscreen ? null : position;
    notifyListeners();
  }

  final List<_OpenDialog> _dialogs = [];
  var _nextDialog = 0;

  @override
  List<DialogSpec> get dialogs => [for (final dialog in _dialogs) dialog.spec];

  @override
  String showDialog(DialogSpec spec) {
    final id = 'dialog#${_nextDialog++}';
    _dialogs.add(_OpenDialog(id, spec));
    notifyListeners();
    return id;
  }

  @override
  void closeDialog(String dialogId) {
    final before = _dialogs.length;
    _dialogs.removeWhere((dialog) => dialog.id == dialogId);
    if (_dialogs.length != before) {
      notifyListeners();
    }
  }

  /// Идентификатор окна вместе с его описанием: описание неизменяемо, а найти
  /// окно надо по тому, что вернули показавшему.
  void _afterChange() {
    _watchActive();
    notifyListeners();
  }

  void _watchActive() {
    final Listenable? listenable = contentAt(activeArea);
    if (identical(listenable, _watched)) {
      return;
    }
    _watched?.removeListener(notifyListeners);
    _watched = listenable;
    _watched?.addListener(notifyListeners);
  }

  void _closeAll(Iterable<ViewportState> leaving) {
    for (final state in leaving) {
      state.close();
    }
  }

  @override
  void dispose() {
    _watched?.removeListener(notifyListeners);
    _watched = null;
    // Приложение уходит — уходит и содержимое областей: открытый редактор
    // держит аренду. Панели закрывает не здесь: их пути ещё не сохранены.
    for (final position in ViewportPosition.values) {
      final stack = _stacks[position]!;
      _closeAll(stack.where((state) => state is! Panel));
      stack.removeWhere((state) => state is! Panel);
    }
    super.dispose();
  }
}

class _OpenDialog {
  const _OpenDialog(this.id, this.spec);

  final String id;
  final DialogSpec spec;
}
