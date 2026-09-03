import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'panel_session.dart';

/// Чтение содержимого: разговор, в котором байты едут кусками.
///
/// Отдельно от работ, и это не дробление: у работы есть ход дела, вопросы и
/// исход, а у чтения — только байты и конец. Смешивать их значило бы дать
/// каждому чтению машинерию, которая ему не нужна
/// (`docs/spec/client-server.md`, §6.2).
class ContentHub {
  ContentHub({
    required ProviderRegistry? registry,
    required PanelSession Function(PanelId panel) sessionOf,
    required void Function(CoreEvent event) say,
  }) : _registry = registry,
       _sessionOf = sessionOf,
       _say = say;

  final ProviderRegistry? _registry;
  final PanelSession Function(PanelId panel) _sessionOf;
  final void Function(CoreEvent event) _say;

  final Map<String, _Reading> _reading = {};

  /// Открывает файл и гонит его байты наружу.
  Future<void> read(String runId, EntryRef entry, {int offset = 0}) async {
    final leases = <ProviderLease>[];
    try {
      final node = await _nodeOf(entry, leases);
      if (node == null) {
        throw const FsError('', FsErrorKind.notFound);
      }
      final provider = node.provider;
      if (provider is! FileContentProvider) {
        // Источник байтов не отдаёт: у списка находок их нет вовсе.
        throw FsError(node.pathString, FsErrorKind.notSupported);
      }

      final reading = _Reading(leases);
      _reading[runId] = reading;

      final stream = await (provider as FileContentProvider).openRead(node, offset: offset);
      await for (final chunk in stream) {
        if (reading.stopped) {
          // Читать больше некому: показ закрыли, курсор ушёл дальше.
          break;
        }
        _say(ContentChunk(runId, chunk));
      }
      _finish(runId, ContentEnded(runId));
    } on FsError catch (error) {
      _finish(runId, ContentEnded(runId, error: error, message: error.message));
    } on Object catch (error) {
      _finish(runId, ContentEnded(runId, message: error.toString()));
    }
  }

  /// Дадут ли записать в этот файл.
  ///
  /// Источник без проверки молчит согласием: спрашивать о правах умеет не
  /// всякий, и выдумывать за него отказ нельзя.
  Future<bool> canWrite(EntryRef entry) async {
    final leases = <ProviderLease>[];
    try {
      final node = await _nodeOf(entry, leases);
      if (node == null) {
        return false;
      }
      final provider = node.provider;
      if (provider is! WriteAccessCheck) {
        return true;
      }
      return await (provider as WriteAccessCheck).canWriteTo(node);
    } on FsError {
      // Не смогли выяснить — не выдумываем: молчим, как источник без проверки.
      return true;
    } finally {
      for (final lease in leases) {
        unawaited(lease.release());
      }
    }
  }

  /// Читать больше не нужно: показ закрыли.
  void stop(String runId) => _reading[runId]?.stopped = true;

  void dispose() {
    for (final reading in _reading.values.toList()) {
      reading.stopped = true;
      reading.release();
    }
    _reading.clear();
  }

  void _finish(String runId, ContentEnded ended) {
    _reading.remove(runId)?.release();
    _say(ended);
  }

  /// Живой узел за ссылкой — и аренда на всё время чтения.
  ///
  /// Аренда здесь не формальность: читают файл из архива, а панель за это время
  /// вправе из него выйти.
  Future<FsNode?> _nodeOf(EntryRef entry, List<ProviderLease> leases) async {
    switch (entry) {
      case PanelEntryRef(:final panel, :final index, :final generation):
        final session = _sessionOf(panel);
        if (generation != session.generation || index < 0 || index >= session.nodes.length) {
          return null;
        }
        if (session.leaseProvider() case final lease?) {
          leases.add(lease);
        }
        return session.nodes[index];
      case PathEntryRef(:final path):
        final resolved = await _registry?.resolveDisplayPath().run(ResolvePathParams(path));
        if (resolved == null) {
          return null;
        }
        if (resolved.lease case final lease?) {
          leases.add(lease);
        }
        return resolved.node;
    }
  }
}

/// Одно идущее чтение: то, что оно держит, и признак «хватит».
class _Reading {
  _Reading(this.leases);

  final List<ProviderLease> leases;
  bool stopped = false;

  void release() {
    for (final lease in leases) {
      unawaited(lease.release());
    }
    leases.clear();
  }
}
