import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'panel_session.dart';

/// Заведённые работы: кто идёт, чем занят и как с ним говорить.
///
/// Работа рождается **здесь**, где живут источники: заявка приносит имя рода и
/// доводы значениями, а ядро разворачивает набор в узлы, находит приёмник и
/// зовёт объявленную модулем фабрику (`docs/spec/client-server.md`, §5.4).
///
/// Наружу работа видна только событиями: ход дела, вопрос, конец. Обратно ей
/// говорят одним входом — отмена, просьба прервать, ответ.
class OperationHub {
  OperationHub({
    required Map<String, OperationRegistration> factories,
    required FcServices services,
    required TreeEditor editor,
    ProviderRegistry? registry,
    MeasuredSizes? sizes,
    required PanelSession Function(PanelId panel) sessionOf,
    required void Function(CoreEvent event) say,
  }) : _factories = factories,
       _services = services,
       _editor = editor,
       _registry = registry,
       _sizes = sizes,
       _sessionOf = sessionOf,
       _say = say;

  final Map<String, OperationRegistration> _factories;
  final FcServices _services;
  final TreeEditor _editor;
  final ProviderRegistry? _registry;

  /// Посчитанные размеры каталогов: своя работа их портит, и забыть их —
  /// её же дело (`docs/spec/directory-sizes.md`, §12.4). null — памяти нет.
  final MeasuredSizes? _sizes;

  final PanelSession Function(PanelId panel) _sessionOf;
  final void Function(CoreEvent event) _say;

  final Map<String, _Run> _running = {};

  /// Не чаще этого отчёты о ходе работы пересекают границу.
  ///
  /// Десять раз в секунду: цифры в полосе хода меняются быстрее, чем глаз
  /// успевает читать, а сообщений через порт становится вчетверо меньше
  /// (`docs/spec/growing-listing.md`, §5). Работа при этом отчитывается
  /// по-прежнему — о границе она не знает.
  static const Duration defaultReportWindow = Duration(milliseconds: 100);

  /// Окно, по которому отчёты придерживаются сейчас.
  ///
  /// Не `const` затем, что проверке случается смотреть **содержимое**
  /// промежуточных отчётов — какой объект в строке источника, какое имя в
  /// строке файла, — а окно их как раз и прячет: работа в прогоне кончается
  /// быстрее, чем оно истекает. Тем же приёмом живёт предел раскрытия дерева
  /// (`PanelSession.expandLimit`).
  @visibleForTesting
  static Duration reportWindow = defaultReportWindow;

  /// Заводит работу и ведёт её до конца.
  ///
  /// Имя работы даёт та сторона: подписка у неё встаёт раньше запуска, и
  /// первое же событие — «начали» — не проходит мимо.
  Future<void> run(String runId, OperationSpec spec) async {
    final declared = _factories[spec.kind];
    if (declared == null) {
      _say(OperationEnded(runId, OperationOutcome.failed, message: 'Нет такой работы: ${spec.kind}'));
      return;
    }

    final leases = <ProviderLease>[];
    try {
      final targets = await _targetsOf(spec.targets, leases);
      final destination = await _destinationOf(spec, leases);

      final operation = declared.factory(_services);
      final run = _Run(operation, leases);
      // Пути собираются **до** старта: после переноса узлов уже нет, а путь
      // забывать всё равно надо. И откуда, и куда: перенос меняет оба конца, а
      // хаб — единственный, кто знает их сразу (§12.4).
      run.touched = declared.writes ? _touchedBy(targets, destination) : const [];
      _running[runId] = run;

      // Сперва подписки, потом запуск: до `start` не происходит ничего, и
      // потерять нечего, — а после первый же вопрос мог бы пройти мимо.
      //
      // Отчёт о ходе работы — это «сейчас идёт вот это», а не запись в журнал:
      // терять промежуточные не жалко, важен последний. Работа же рассказывает
      // о себе столько, сколько ей естественно: поиск — на каждый каталог,
      // копирование — на каждый блок. Ограничитель стоит здесь, на самой
      // границе, и один на все работы сразу
      // (`docs/spec/growing-listing.md`, §5).
      run.reports = Throttle(() => _say(OperationProgress(runId, _reportOf(operation))), interval: () => reportWindow);
      run.watch(onProgress: run.reports!.call, onAsk: (request) => _ask(runId, run, request));

      operation.start(
        OperationInputs(
          targets: targets,
          destination: destination,
          editor: _editor,
          options: spec.options,
          onFound: (found) => _collect(runId, found),
        ),
      );

      await operation.result;
      _finish(runId, OperationEnded(runId, OperationOutcome.done));
    } on OperationCanceled {
      _finish(runId, OperationEnded(runId, OperationOutcome.canceled));
    } on FsError catch (error) {
      _finish(runId, OperationEnded(runId, OperationOutcome.failed, error: error, message: error.message));
    } on Object catch (error) {
      // Чужая беда переносится текстом: тип через границу не поедет, а текст —
      // это всё, что скажут человеку.
      _finish(runId, OperationEnded(runId, OperationOutcome.failed, message: error.toString()));
    }
  }

  /// Реплика в идущую работу.
  void tell(String runId, OperationInput input) {
    final run = _running[runId];
    if (run == null) {
      // Работы уже нет: сказать мёртвому — тишина, а не ошибка.
      return;
    }
    switch (input) {
      case CancelInput():
        run.operation.cancel();
      case SoftCancelInput():
        // Здешняя работа просьбу не исполняет, а передаёт: вопрос «прервать?»
        // задаёт она сама между своими шагами.
        run.operation.requestCancel();
      case AnswerInput(:final optionId, :final text):
        run.answer(optionId, text);
      case ShellInput():
      case ShellResize():
        // Не сюда: у оболочки свои разговоры, и сервер отдаёт их ей раньше.
        break;
    }
  }

  /// Найденное — той стороне значениями, а узлы остаются здесь.
  ///
  /// Складывать их где-то ещё не нужно: список принадлежит источнику, в
  /// который работа их и кладёт (`docs/spec/file-search.md`, §4.2). Здесь
  /// только весть наружу — для счётчика и полоски.
  void _collect(String runId, List<FsNode> found) {
    if (found.isEmpty) {
      return;
    }
    _say(OperationFound(runId, [for (final node in found) entryValueOf(node)]));
  }

  /// Прекращает всё: приложение уходит.
  void dispose() {
    for (final run in _running.values.toList()) {
      run.operation.cancel();
      run.release();
    }
    _running.clear();
  }

  void _ask(String runId, _Run run, OperationRequest request) {
    run.asked = request;
    _say(
      OperationAsked(
        runId,
        AskSpec(
          message: request.message,
          options: {for (final option in request.options) option.id: option.label},
          enterOptionId: request.enterOption.id,
          escapeOptionId: request.escapeOption?.id,
          inputLabel: request.inputLabel,
          secret: request.secret,
        ),
      ),
    );
  }

  void _finish(String runId, OperationEnded ended) {
    final run = _running.remove(runId);
    // Забывание — **до** «работа кончилась»: та сторона по этому событию
    // перечитывает панели, и опоздай мы — она успела бы нарисовать вчерашние
    // числа. Оборванная работа забывает наравне с дошедшей до конца: половину
    // написать она успела (`docs/spec/directory-sizes.md`, §12.4).
    if (run != null) {
      _forgetMeasured(run);
    }
    // Придержанный отчёт отдаётся **до** «работа кончилась»: иначе итог остался
    // бы с числом на сотню миллисекунд младше правды — на поиске это «нашлось
    // 12300» вместо 12487 (`docs/spec/growing-listing.md`, §5).
    run?.reports?.flush();
    run?.release();
    if (run?.asked != null) {
      // Вопрос снимается вместе с работой: спрашивать уже нечего, а закрыть
      // окно с той стороны иначе некому.
      _say(OperationAskCanceled(runId));
    }
    _say(ended);
  }

  /// Что задела работа: откуда брала и куда клала.
  ///
  /// Каталог цели — сам путь (память заодно уносит его поддерево и предков);
  /// файл — каталог, в котором он лежит: изменился он, а не файл сам по себе.
  List<String> _touchedBy(List<FsNode> targets, DirectoryNode? destination) {
    if (_sizes == null) {
      return const [];
    }
    final paths = <String>{};
    for (final node in targets) {
      paths.add(node is DirectoryNode ? node.pathString : (node.parent?.pathString ?? node.pathString));
    }
    if (destination != null) {
      paths.add(destination.pathString);
    }
    return paths.toList();
  }

  void _forgetMeasured(_Run run) {
    final sizes = _sizes;
    if (sizes == null) {
      return;
    }
    for (final path in run.touched) {
      sizes.forget(path);
    }
  }

  ProgressReport _reportOf(Operation<Object?, Object?> operation) {
    final status = operation.status;
    return status is MutableOperationStatus
        ? status.report
        : ProgressReport(state: status.state, message: status.message);
  }

  /// Разворачивает имя набора в узлы — и берёт аренду на то, из чего читают.
  ///
  /// Аренда здесь, а не у команды: работу можно отправить в фон, и панель за
  /// это время вправе выйти из архива, в котором она идёт. Держать источник
  /// живым — дело той стороны, где он и живёт.
  Future<List<FsNode>> _targetsOf(Targets targets, List<ProviderLease> leases) async {
    switch (targets) {
      case MarkedTargets(:final panel, :final under):
        final session = _sessionOf(panel);
        _hold(session, leases);
        // Пометка чужого каталога разбирается асинхронно, а просьбы ядром не
        // сериализуются: пометил ветвь в дереве — тут же нажал `F8`, и работа
        // прочитала бы недособранное (`docs/spec/operation-targets.md`, §3).
        await session.marksSettled;
        return session.targetNodesUnder(_rowOf(under, leases));
      case RowTargets(:final row):
        final node = _rowOf(row, leases);
        return node == null || node is ParentDirNode ? const [] : [node];
      case PathTargets(:final paths):
        final registry = _registry;
        if (registry == null) {
          return const [];
        }
        // Пути разбирает **корень дерева**, а не панель: путь пришёл со
        // стороны — из системы, из сценария, — и к тому месту, где стоит
        // панель, отношения не имеет. Разбор панелью тут уже соврал однажды:
        // `/Users/…`, брошенный в архив на сервере, искался на сервере.
        final nodes = <FsNode>[];
        for (final path in paths) {
          final resolved = await registry.resolveDisplayPath().run(ResolvePathParams(path));
          if (resolved.lease case final lease?) {
            leases.add(lease);
          }
          final node = resolved.node;
          if (node == null) {
            throw FsError(path, FsErrorKind.notFound);
          }
          nodes.add(node);
        }
        return nodes;
    }
  }

  /// Узел названной строки; null — строки нет или её не назвали.
  ///
  /// Строку называет тот, кто заводил работу, — своей, а не ядровой личностью
  /// (`docs/spec/client-server.md`, §5.6). Разбирает её сессия по своим
  /// строкам: глобального разбора пути здесь не появляется (§5.5а).
  FsNode? _rowOf(EntryRef? row, List<ProviderLease> leases) {
    switch (row) {
      case null:
        return null;
      case PanelEntryRef(:final panel, :final id, :final path):
        final session = _sessionOf(panel);
        _hold(session, leases);
        return session.rowForRef(id, path);
      case PathEntryRef():
        // Адрес со стороны целям работы не приходит: для него есть свой набор
        // (`Targets.paths`), и разбирает его корень дерева.
        return null;
    }
  }

  /// Каталог-приёмник: путь, разобранный тем, кто его назвал.
  ///
  /// Панель разбирает **свой** путь, когда приёмник назван ею: путь может
  /// проходить через несколько источников («…/archive.zip:zip:/inner»), и
  /// разбирает его та панель, которая там стоит. Аренда здесь не формальность —
  /// архив по дороге монтируется ради этой работы, и отпустить его, кроме неё,
  /// некому.
  ///
  /// Каталога у панели ядро не спрашивает вовсе: место приезжает названным
  /// (`docs/spec/client-server.md`, §5.6а).
  Future<DirectoryNode?> _destinationOf(OperationSpec spec, List<ProviderLease> leases) async {
    final (PanelSession? session, String? raw) = switch (spec.destination) {
      PanelDestination(:final panel, :final path) => (_sessionOf(panel), path),
      PathDestination(:final path) => (null, path),
      null => (null, null),
    };
    if (raw == null) {
      return null;
    }

    final path = raw.trim();
    if (path.isEmpty) {
      throw const FsError('', FsErrorKind.invalidName);
    }
    final resolved =
        session != null
            ? await session.resolvePath().run(path)
            : await _registry?.resolveDisplayPath().run(ResolvePathParams(path)) ?? const ResolvedNode.none();
    if (resolved.lease case final lease?) {
      leases.add(lease);
    }
    var node = resolved.node;
    if (node is LinkNode) {
      // Ссылка на каталог — тоже каталог: копировать «в неё» можно.
      node = await node.provider.resolveLink().run(node);
    }
    if (node == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node is! DirectoryNode) {
      throw FsError(path, FsErrorKind.notADirectory);
    }
    return node;
  }

  void _hold(PanelSession session, List<ProviderLease> leases) {
    if (session.leaseProvider() case final lease?) {
      leases.add(lease);
    }
  }
}

/// Одна идущая работа: сама операция, её подписки и то, что она держит.
class _Run {
  _Run(this.operation, this.leases);

  final Operation<OperationInputs, void> operation;
  final List<ProviderLease> leases;

  /// Чем отчёты о ходе работы придерживаются на пути через границу.
  Throttle? reports;

  StreamSubscription<OperationRequest>? _requests;
  VoidCallback? _stopWatching;

  /// Вопрос, на который ждут ответа; null — работа не спрашивает.
  OperationRequest? asked;

  /// Каталоги, посчитанные размеры которых эта работа делает вчерашними.
  /// Собраны до старта: после переноса узлов уже нет.
  List<String> touched = const [];

  void watch({required VoidCallback onProgress, required void Function(OperationRequest request) onAsk}) {
    final status = operation.status;
    status.addListener(onProgress);
    _stopWatching = () => status.removeListener(onProgress);
    _requests = operation.requests.listen(onAsk);
  }

  void answer(String optionId, String text) {
    final request = asked;
    if (request == null) {
      return;
    }
    final option = request.options.where((candidate) => candidate.id == optionId).firstOrNull;
    if (option == null) {
      return;
    }
    asked = null;
    request.respond(option, text: text);
  }

  void release() {
    reports?.cancel();
    _stopWatching?.call();
    unawaited(_requests?.cancel());
    for (final lease in leases) {
      unawaited(lease.release());
    }
    leases.clear();
  }
}
