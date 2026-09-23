import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Распаковка архива **рядом с ним самим** — работа ядра.
///
/// Это перенос, у которого источник смонтирован: архив открывается тем же
/// вложенным провайдером, что и по `Enter`, а дальше идёт обычное копирование
/// движком. Отсюда даром достаётся всё, что перенос умеет: полоса, `Esc`,
/// вопросы о занятом имени, потоковое чтение, права и ссылки
/// (`docs/spec/archive-here.md`, §3).
class ArchiveExtraction {
  ArchiveExtraction({required ProviderRegistry registry, required FileNaming naming})
    : _registry = registry,
      _naming = naming;

  /// Имя работы: под ним её и зовут из команды.
  static const String kind = 'archive.extract';

  final ProviderRegistry _registry;

  /// Как имя делится на основу и расширение: `архив.tar.gz` → `архив`
  /// (составные расширения, Б5).
  final FileNaming _naming;

  Operation<OperationInputs, void> operation() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      for (final target in inputs.targets) {
        op.checkCanceled();
        await _extractOne(op, inputs, target);
      }
    });
  }

  /// Один архив: смонтировать, решить про каталог и скопировать.
  ///
  /// Приёмник **не спрашивается у заявки**: место у каждого архива своё — тот
  /// каталог, где он лежит. Помеченные в разных ветвях дерева разъезжаются
  /// каждый к себе (§2).
  Future<void> _extractOne(TaskOperation<Object?, Object?> op, OperationInputs inputs, FsNode target) async {
    final scheme = _registry.schemeFor(target);
    final where = target.parentDirectory;
    if (scheme == null || where == null) {
      // Не архив или лежит неизвестно где — молча мимо: в целях бывает всякое,
      // а команда уже отобрала раскрываемые строки.
      return;
    }

    final lease = await op.delegate(_registry.acquire(), AcquireParams(scheme, target));
    try {
      final root = lease.provider.rootDirectory;
      final inside = [
        for (final node in await lease.provider.listChildren(root))
          if (node is! ParentDirNode) node,
      ];
      if (inside.isEmpty) {
        return;
      }
      final destination = await _destinationFor(op, inputs, target, where, inside);
      await op.delegate(inputs.editor.copy(), TransferParams(inside, destination));
    } finally {
      // Аренда живёт ровно столько, сколько работа: открытый архив не должен
      // пережить распаковку (`docs/spec/provider-lease.md`).
      await lease.release();
    }
  }

  /// Куда лечь содержимому: рядом или в заведённый каталог.
  ///
  /// Один узел в корне — как есть. Россыпь — каталог по основе имени: иначе
  /// одно нажатие рассыпает двести файлов поверх соседей, и убирать их человеку
  /// придётся руками (§3.1).
  Future<DirectoryNode> _destinationFor(
    TaskOperation<Object?, Object?> op,
    OperationInputs inputs,
    FsNode archive,
    DirectoryNode where,
    List<FsNode> inside,
  ) async {
    if (inside.length == 1) {
      return where;
    }
    final name = _naming.split(archive.name).base;
    return op.delegate(inputs.editor.makeDirectory(), MakeDirectoryParams(where, name.isEmpty ? archive.name : name));
  }
}
