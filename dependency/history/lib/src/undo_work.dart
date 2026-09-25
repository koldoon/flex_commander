import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'undo_trace.dart';

/// Имя работы отката и её доводы.
abstract final class HistoryOperations {
  static const String undo = 'history.undo';

  /// Журнал отменяемой работы — списком записей словарями.
  ///
  /// Значениями, а не объектом: доводы едут через границу, и разбирать их
  /// ядру по типу нечем. Тем же приёмом возит пары групповое переименование.
  static const String journal = 'journal';
}

/// Откат по журналу: идёт снизу вверх и зовёт те же примитивы, что и перенос
/// (`docs/spec/operation-history.md`, §9).
///
/// Цели у работы пустые: каждый путь она разбирает сама. Иначе хаб уронил бы
/// её на первом же пути, которого уже нет, — а «уже нет» для отмены обычное
/// дело: пропускаем молча.
class UndoWork {
  const UndoWork({required this.strings, required this.registry});

  final Strings strings;
  final ProviderRegistry registry;

  Operation<OperationInputs, void> operation() => TaskOperation<OperationInputs, void>((op, inputs) async {
    final entries = [
      for (final item in inputs.options[HistoryOperations.journal] as List<Object?>? ?? const [])
        if (JournalEntry.fromMap(item) case final entry?) entry,
    ];
    if (entries.isEmpty) {
      return;
    }

    traceUndo('начали: ${entries.length} записей');
    final undo = _Undo(op: op, inputs: inputs, registry: registry, strings: strings);
    try {
      // Снизу вверх: последнее сделанное отменяется первым — иначе возвращённое
      // на место тут же перекрыл бы откат того, что делалось до него.
      for (final (at, entry) in entries.reversed.indexed) {
        await op.checkpoint();
        // Счёт виден в окне: иначе на большом журнале оно выглядит вставшим.
        op.report(message: strings.tr('Undoing…'), itemsTransferred: at, itemsTotal: entries.length);
        traceUndo('запись ${at + 1}/${entries.length}: ${entry.toMap()}');
        await undo.one(entry);
        traceUndo('запись ${at + 1} отменена');
      }
    } finally {
      // Накопленное применяется в конце: у архива запись — это пересборка, и
      // делать её на каждый объект значило бы переписывать его столько раз,
      // сколько их в журнале.
      await undo.closeBatches();
      traceUndo('кончили');
    }
  });
}

/// Один проход отмены: держит ответы «…все» и аренды разобранных путей.
class _Undo {
  _Undo({required this.op, required this.inputs, required this.registry, required this.strings});

  final TaskOperation<Object?, void> op;
  final OperationInputs inputs;
  final ProviderRegistry registry;
  final Strings strings;

  bool _skipAll = false;

  /// Провайдеры, которым запись открыта пачкой: закрываются в конце.
  final List<BatchedWrites> _batches = [];

  /// Открыть пачку записей, если провайдер их копит (архивы).
  ///
  /// Без этого архив пересобирался бы на каждый объект: у него запись — это
  /// пересборка целиком (`docs/spec/archive-write-back.md`).
  Future<void> _openBatch(FsNode node) async {
    final provider = node.provider;
    if (provider is! BatchedWrites) {
      return;
    }
    final batch = provider as BatchedWrites;
    if (_batches.any((opened) => identical(opened, batch))) {
      return;
    }
    traceUndo('открываем пачку записей: ${provider.runtimeType}');
    _batches.add(batch);
    await batch.beginWrites(op);
  }

  /// Закрыть все открытые пачки — чем бы работа ни кончилась.
  Future<void> closeBatches() async {
    for (final batch in _batches) {
      traceUndo('закрываем пачку: ${batch.runtimeType}');
      await batch.endWrites(op);
    }
    _batches.clear();
  }

  Future<void> one(JournalEntry entry) async {
    switch (entry) {
      case Created():
        await _remove(entry);
      case Moved(:final from, :final to):
        await _back(from: from, to: to, entry: entry);
      case Trashed(:final from, :final to):
        await _back(from: from, to: to, entry: entry);
      case Destroyed():
        // Сюда не доходит: одна такая запись делает работу неотменимой
        // целиком, и до отмены дело не доходит вовсе (§7).
        break;
    }
  }

  /// Удалить созданное — если это всё ещё оно.
  Future<void> _remove(Created entry) async {
    final found = await _resolve(entry.path);
    final node = found?.node;
    if (node == null) {
      // Объекта уже нет: кто-то убрал его до нас, и отменять нечего.
      await found?.release();
      return;
    }
    try {
      if (node is DirectoryNode && !entry.whole) {
        // Пустой каталог сносится, только если он так и остался пуст: в нём
        // могло появиться чужое. Каталог, созданный копированием целиком,
        // уходит деревом — там всё сделала эта работа (§6).
        final children = await node.provider.listChildren(node);
        if (children.isNotEmpty) {
          return;
        }
      } else if (node is! DirectoryNode && !await _isSame(node, entry) && !await _agreesToDelete(entry.path)) {
        return;
      }

      final editor = _editorOf(node);
      if (editor == null) {
        traceUndo('провайдер не умеет писать: ${entry.path}');
        return;
      }
      await _openBatch(node);
      traceUndo('удаляем ${node.pathString}');
      if (!await editor.deleteTree(node)) {
        await editor.deleteEntry(node);
      }
      traceUndo('удалили ${node.pathString}');
    } finally {
      await found?.release();
    }
  }

  /// Вернуть объект туда, откуда он уехал.
  Future<void> _back({required String from, required String to, required JournalEntry entry}) async {
    final found = await _resolve(to);
    final node = found?.node;
    if (node == null) {
      await found?.release();
      return;
    }

    final place = _placeOf(from);
    final home = await _resolve(place.directory);
    final parent = home?.node;
    try {
      if (parent is! DirectoryNode) {
        return;
      }
      final editor = _editorOf(node);
      if (editor == null) {
        return;
      }
      // Занято — спрашиваем: вернуть поверх чужого значило бы потерять его.
      final taken = await editor.lookup(parent, place.name);
      if (taken != null && !await _agreesToDelete(from)) {
        return;
      }

      await _openBatch(node);
      traceUndo('возвращаем ${node.pathString} → ${parent.pathString}/${place.name}');
      if (!await editor.renameEntry(node, parent, place.name)) {
        // Провайдер так не умеет — переносим движком, той же дорогой, какой
        // объект сюда и приехал.
        await op.delegate(inputs.editor.move(), TransferParams([node], parent));
      }
    } finally {
      await found?.release();
      await home?.release();
    }
  }

  Future<ResolvedNode?> _resolve(String path) async {
    traceUndo('разбираем путь $path');
    try {
      final resolved = await registry.resolveDisplayPath().run(ResolvePathParams(path));
      traceUndo('разобрали $path → ${resolved.node?.pathString ?? 'ничего'}');
      return resolved;
    } on FsError {
      // Путь не разобрался: источника, в котором это лежало, больше нет.
      return null;
    }
  }

  /// Тот ли это объект, каким его записали.
  Future<bool> _isSame(FsNode node, Created entry) async {
    if (entry.size != FileEntry.unknownSize && node.size != entry.size) {
      return false;
    }
    final modified = entry.modified;
    if (modified != null && node is FileNode && node.modified != null) {
      return node.modified!.difference(modified).inSeconds.abs() < 1;
    }
    return true;
  }

  /// Спросить про изменившееся — тем же словарём, что и перенос.
  Future<bool> _agreesToDelete(String path) async {
    if (_skipAll) {
      return false;
    }
    final answer = await op.ask(
      OperationRequest(
        message: strings.tr('{path} changed since then', args: {'path': path}),
        options: const [
          TransferAnswers.overwrite,
          TransferAnswers.skip,
          TransferAnswers.skipAll,
          TransferAnswers.cancel,
        ],
        // Молча трогать изменившееся нельзя.
        enterOption: TransferAnswers.skip,
      ),
    );
    if (answer == TransferAnswers.cancel) {
      throw const OperationCanceled();
    }
    if (answer == TransferAnswers.skipAll) {
      _skipAll = true;
      return false;
    }
    return answer == TransferAnswers.overwrite;
  }

  NodeEditor? _editorOf(FsNode node) => node.provider is NodeEditor ? node.provider as NodeEditor : null;

  ({String directory, String name}) _placeOf(String path) {
    final at = path.lastIndexOf('/');
    if (at <= 0) {
      return (directory: '/', name: path.substring(at + 1));
    }
    return (directory: path.substring(0, at), name: path.substring(at + 1));
  }
}
