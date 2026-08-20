import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Ошибки, которые никто не поймал.
///
/// Приложение до сих пор молчало о поломках: единственная ловушка писала в
/// консоль, и человек видел лишь то, что «не сработало». Предусмотреть всё
/// заранее нельзя, значит нужен общий приём — показать, что случилось, и дать
/// это скопировать.
///
/// Сюда идёт только **непойманное**. Отказы, о которых команда сообщает сама
/// (`FsError` в её окне, вопросы операций), остаются там: одна и та же беда,
/// показанная дважды, выглядит как две разные.
class ErrorController extends ChangeNotifier implements Errors {
  ErrorController({this.clipboard, this.version, this.onLog, Map<String, String>? environment})
    : environment = environment ?? _machine();

  /// Сведения о машине и сборке — в отчёт. Задаются параметром, чтобы тест
  /// сверял точный текст, а не то, на чём его запустили.
  static Map<String, String> _machine() => {
    'Platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'Dart': Platform.version,
  };

  /// Куда копировать отчёт. null — копировать некуда (тесты без службы).
  final ClipboardService? clipboard;

  /// Версия приложения для отчёта.
  final String? version;

  /// Что дописывается в отчёт про машину и сборку.
  final Map<String, String> environment;

  /// Куда писать в журнал: ошибка должна остаться в логе, даже если окно
  /// закрыли не глядя.
  final void Function(ErrorReport report)? onLog;

  /// Сколько ошибок держим. Шквал не должен съесть память: дальше первых
  /// нескольких всё равно смотрят в журнал.
  static const int maxPending = 20;

  final List<ErrorReport> _queue = [];

  @override
  ErrorReport? get current => _queue.isEmpty ? null : _queue.first;

  @override
  int get pending => _queue.length;

  /// Ошибка, которую никто не поймал.
  @override
  void report(Object error, [StackTrace? stack, String? context]) {
    final report = ErrorReport(error: error, stack: stack, context: context);
    onLog?.call(report);

    final last = _queue.isEmpty ? null : _queue.last;
    if (last != null && last.sameAs(report)) {
      // Та же самая: не плодим окна, а считаем повторы.
      _queue[_queue.length - 1] = last.repeated();
      notifyListeners();
      return;
    }

    if (_queue.length >= maxPending) {
      return;
    }

    _queue.add(report);
    notifyListeners();
  }

  /// Закрыть показанную и показать следующую.
  @override
  void dismiss() {
    if (_queue.isEmpty) {
      return;
    }
    _queue.removeAt(0);
    notifyListeners();
  }

  /// Кладёт отчёт о показанной ошибке в буфер обмена.
  ///
  /// Пока это и есть «сообщить»: отправлять некуда, а вставить отчёт в задачу
  /// или письмо можно уже сейчас.
  @override
  Future<bool> copyReport() async {
    final report = current;
    final clipboard = this.clipboard;
    if (report == null || clipboard == null) {
      return false;
    }

    await clipboard.writeText(report.toReport(environment: {if (version != null) 'Version': version!, ...environment}));
    return true;
  }
}
