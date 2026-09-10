import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'attribute_edits.dart';

/// Работа `attrs.apply`: назначить атрибуты — одному объекту или дереву.
///
/// Живёт в ядре, там же, где источники: правка одного объекта — вызов
/// провайдера, а правка дерева — обход с прогрессом, отменой и вопросами.
/// Экрану достаётся только заявка со значениями.
class AttributesApply {
  const AttributesApply(this.strings);

  final Strings strings;

  Operation<OperationInputs, void> operation() =>
      TaskOperation<OperationInputs, void>((op, inputs) => _run(op, inputs));

  Future<void> _run(TaskOperation<OperationInputs, void> op, OperationInputs inputs) async {
    final edits = AttributeEdits.fromOptions(inputs.options);
    if (edits.isEmpty || inputs.targets.isEmpty) {
      // Открыли окно и закрыли, ничего не тронув: работа честно ничего не
      // делает, а не выдумывает себе занятие.
      return;
    }

    // Названные объекты правятся **всегда**: их выбрали руками, и отбор
    // относится к тому, что нашлось внутри.
    var done = 0;
    var skipAll = false;

    Future<bool> handle(FsNode node, {required bool named}) async {
      if (!named && !edits.reaches(isDirectory: node is DirectoryNode)) {
        return true;
      }
      await op.checkpoint();
      op.report(
        message: strings.tr('Changing attributes…'),
        itemName: node.name,
        itemsTransferred: ++done,
        itemsTotal: edits.recursive ? null : inputs.targets.length,
        indeterminate: edits.recursive,
      );
      try {
        await _applyTo(node, edits);
        return true;
      } on FsError catch (error) {
        if (skipAll) {
          return true;
        }
        final answer = await op.ask(
          OperationRequest(
            message: strings.describe(error),
            options: const [TransferAnswers.skip, TransferAnswers.skipAll, TransferAnswers.cancel],
            enterOption: TransferAnswers.skip,
            escapeOption: TransferAnswers.cancel,
          ),
        );
        skipAll = skipAll || answer.id == TransferAnswers.skipAll.id;
        // Права на дереве почти всегда разъезжаются в одном-двух местах, и
        // «отменить всё из-за одного» означало бы, что рекурсией пользоваться
        // нельзя.
        return answer.id != TransferAnswers.cancel.id;
      }
    }

    for (final target in inputs.targets) {
      if (!await handle(target, named: true)) {
        return;
      }
      if (!edits.recursive || target is! DirectoryNode) {
        continue;
      }
      await for (final event in walkTree(target)) {
        // Сам корень обхода — это уже названный объект, и править его дважды
        // незачем.
        if (event is! WalkedNode || identical(event.node, target)) {
          continue;
        }
        if (!await handle(event.node, named: false)) {
          return;
        }
      }
    }
  }

  /// Всё, что просили, — одному объекту.
  Future<void> _applyTo(FsNode node, AttributeEdits edits) async {
    final provider = node.provider;

    if (edits.setBits != 0 ||
        edits.clearBits != 0 ||
        edits.modified != null ||
        edits.accessed != null ||
        edits.uid != null ||
        edits.gid != null) {
      if (provider is! NodeAttributesEditor) {
        throw FsError(node.pathString, FsErrorKind.notSupported);
      }
      final editor = provider as NodeAttributesEditor;

      if (edits.setBits != 0 || edits.clearBits != 0) {
        await editor.setMode(node, edits.applyToMode(await _modeOf(editor, node, edits)));
      }
      if (edits.modified != null || edits.accessed != null) {
        await editor.setTimes(node, modified: edits.modified, accessed: edits.accessed);
      }
      if (edits.uid != null || edits.gid != null) {
        await editor.setOwner(node, uid: edits.uid, gid: edits.gid);
      }
    }

    if (edits.xattrSet.isEmpty && edits.xattrRemove.isEmpty) {
      return;
    }
    if (provider is! NodeXattrEditor) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }
    final xattr = provider as NodeXattrEditor;
    for (final one in edits.xattrSet.entries) {
      await xattr.setXattr(node, one.key, one.value);
    }
    for (final name in edits.xattrRemove) {
      await xattr.removeXattr(node, name);
    }
  }

  /// Нынешний режим объекта — и только тогда, когда он вправду нужен.
  ///
  /// Если маски покрывают все двенадцать битов, новый режим от старого не
  /// зависит вовсе, и спрашивать неоткуда: на дереве в десять тысяч файлов это
  /// десять тысяч лишних системных вызовов. Так бывает всегда, когда правят
  /// один объект или набирают восьмеричное руками.
  Future<int> _modeOf(NodeAttributesEditor editor, FsNode node, AttributeEdits edits) async {
    if ((edits.setBits | edits.clearBits) & AttributeEdits.modeMask == AttributeEdits.modeMask) {
      return 0;
    }
    return (await editor.readAttributes(node)).mode;
  }
}
