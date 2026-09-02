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
    required Map<String, OperationFactory> factories,
    required FcServices services,
    required TreeEditor editor,
    ProviderRegistry? registry,
    required PanelSession Function(PanelId panel) sessionOf,
    required void Function(CoreEvent event) say,
  }) : _factories = factories,
       _services = services,
       _editor = editor,
       _registry = registry,
       _sessionOf = sessionOf,
       _say = say;

  final Map<String, OperationFactory> _factories;
  final FcServices _services;
  final TreeEditor _editor;
  final ProviderRegistry? _registry;
  final PanelSession Function(PanelId panel) _sessionOf;
  final void Function(CoreEvent event) _say;

  final Map<String, _Run> _running = {};

  /// Заводит работу и ведёт её до конца.
  ///
  /// Имя работы даёт та сторона: подписка у неё встаёт раньше запуска, и
  /// первое же событие — «начали» — не проходит мимо.
  Future<void> run(String runId, OperationSpec spec) async {
    final factory = _factories[spec.kind];
    if (factory == null) {
      _say(OperationEnded(runId, OperationOutcome.failed, message: 'Нет такой работы: ${spec.kind}'));
      return;
    }

    final leases = <ProviderLease>[];
    try {
      final targets = await _targetsOf(spec.targets, leases);
      final destination = await _destinationOf(spec, leases);

      final operation = factory(_services);
      final run = _Run(operation, leases);
      _running[runId] = run;

      // Сперва подписки, потом запуск: до `start` не происходит ничего, и
      // потерять нечего, — а после первый же вопрос мог бы пройти мимо.
      run.watch(
        onProgress: () => _say(OperationProgress(runId, _reportOf(operation))),
        onAsk: (request) => _ask(runId, run, request),
      );

      operation.start(
        OperationInputs(targets: targets, destination: destination, editor: _editor, options: spec.options),
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
    }
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
    run?.release();
    if (run?.asked != null) {
      // Вопрос снимается вместе с работой: спрашивать уже нечего, а закрыть
      // окно с той стороны иначе некому.
      _say(OperationAskCanceled(runId));
    }
    _say(ended);
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
      case MarkedTargets(:final panel):
        final session = _sessionOf(panel);
        _hold(session, leases);
        return session.targetNodes;
      case CurrentTargets(:final panel):
        final session = _sessionOf(panel);
        _hold(session, leases);
        final node = session.currentNode;
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

  /// Каталог-приёмник: панель, путь — или путь, разобранный **от панели**.
  ///
  /// Разбор ведёт панель-приёмник, когда она названа: путь может проходить
  /// через несколько источников («…/archive.zip:zip:/inner»), и одному
  /// источнику такое не по силам. Аренда здесь не формальность — архив по
  /// дороге монтируется ради этой работы, и отпустить его, кроме неё, некому.
  Future<DirectoryNode?> _destinationOf(OperationSpec spec, List<ProviderLease> leases) async {
    final session = spec.destination == null ? null : _sessionOf(spec.destination!);

    if (spec.destinationPath case final raw?) {
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

    if (session != null) {
      _hold(session, leases);
      return session.directory;
    }
    return null;
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

  StreamSubscription<OperationRequest>? _requests;
  VoidCallback? _stopWatching;

  /// Вопрос, на который ждут ответа; null — работа не спрашивает.
  OperationRequest? asked;

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
    _stopWatching?.call();
    unawaited(_requests?.cancel());
    for (final lease in leases) {
      unawaited(lease.release());
    }
    leases.clear();
  }
}
