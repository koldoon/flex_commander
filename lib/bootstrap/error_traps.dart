import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

/// Ловушки для того, что никто не поймал.
///
/// Две, и обе нужны: [FlutterError.onError] ловит каркас (сборка, раскладка,
/// отрисовка, жесты), а [PlatformDispatcher.onError] — асинхронное, до
/// которого каркасу дела нет. Ошибки наших изолятов приходят обычным путём:
/// `Isolate.run` отдаёт их тому, кто ждал.
///
/// Чужой изолят, который печатает своё исключение сам и наружу не отдаёт
/// (`isolate_manager` внутри `re_editor`), поймать нельзя — оно остаётся в
/// консоли. Врать о полноте покрытия не стоит.
///
/// Отдельно от `main`, чтобы это можно было проверить тестом: ловушки —
/// единственное место, где решается, увидит ли человек поломку вообще.
class ErrorTraps {
  ErrorTraps({this.log});

  /// Куда писать в журнал: ошибка должна остаться в логе, даже если окно
  /// закрыли не глядя.
  final void Function(Object error, StackTrace? stack)? log;

  Errors? _sink;

  /// Пойманное до того, как приложение собрано.
  ///
  /// Поломка при запуске — тоже поломка, и терять её нельзя: показать её
  /// некому, но как только окно появится, она там окажется.
  final List<(Object, StackTrace?, String?)> _early = [];

  int get pendingEarly => _early.length;

  /// Ставит ловушки. До [attach] пойманное копится.
  void install() {
    FlutterError.onError = (details) => handle(details.exception, details.stack, details.context?.toString());
    PlatformDispatcher.instance.onError = (error, stack) {
      handle(error, stack, null);
      // true — «разобрались»: иначе среда ещё раз напечатает то же самое, а
      // показать это всё равно больше некому.
      return true;
    };
  }

  /// Отдаёт сборщику накопленное и всё дальнейшее.
  void attach(Errors errors) {
    _sink = errors;
    for (final (error, stack, context) in _early) {
      errors.report(error, stack, context);
    }
    _early.clear();
  }

  /// Пойманная ошибка: в журнал и в окно.
  void handle(Object error, StackTrace? stack, [String? context]) {
    log?.call(error, stack);

    final sink = _sink;
    if (sink == null) {
      _early.add((error, stack, context));
      return;
    }
    sink.report(error, stack, context);
  }
}
