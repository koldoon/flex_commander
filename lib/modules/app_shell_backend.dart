import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Оболочка приложения — ядровая половина.
///
/// Движок переноса и работы, которые им выполняются: копирование, перенос,
/// удаление, создание каталога, переименование. Есть они у файлового менеджера
/// всегда, поэтому и объявляются здесь, а не модулем.
///
/// Сами работы — тонкие: всё, что они делают, это зовут движок теми доводами,
/// которые приехали в заявке. Разворачивать набор в узлы, искать приёмник и
/// держать аренду — дело ядра, и делает оно это один раз для всех
/// (`docs/spec/client-server.md`, §5.4).
class AppShellBackend implements FcBackendModule {
  const AppShellBackend();

  @override
  String get id => 'fc.shell';

  @override
  String get title => 'Application shell';

  @override
  void installBackend(BackendRegistry registry) {
    // Движок один на приложение: состояния у него нет, а источники узлы
    // приносят с собой — в том числе разные у источника и приёмника.
    registry.service<TreeEditor>((services) => const TreeTransferEngine());

    registry.operation(FileOperations.copy, (services) => _transfer(moves: false));
    registry.operation(FileOperations.move, (services) => _transfer(moves: true));

    registry.operation(
      FileOperations.remove,
      (services) => TaskOperation<OperationInputs, void>(
        (op, inputs) => op.delegate(
          inputs.editor.remove(),
          RemoveParams(inputs.targets, toTrash: inputs.option<bool>(FileOperations.toTrash) ?? true),
        ),
      ),
    );

    registry.operation(
      FileOperations.makeDirectory,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final parent = inputs.destination;
        final name = inputs.option<String>(FileOperations.name) ?? '';
        if (parent == null || name.isEmpty) {
          throw FsError(name, FsErrorKind.invalidName);
        }
        await op.delegate(inputs.editor.makeDirectory(), MakeDirectoryParams(parent, name));
      }),
    );

    registry.operation(
      FileOperations.measure,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final node = inputs.targets.firstOrNull;
        if (node == null) {
          return;
        }
        await op.delegate(node.provider.calculateSize(), inputs.targets);
      }),
    );

    registry.operation(
      FileOperations.rename,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final node = inputs.targets.firstOrNull;
        final name = inputs.option<String>(FileOperations.name) ?? '';
        if (node == null || name.isEmpty) {
          throw FsError(name, FsErrorKind.invalidName);
        }
        await op.delegate(inputs.editor.rename(), RenameParams(node, name));
      }),
    );
  }

  /// Копирование и перенос — одна работа с одним отличием.
  ///
  /// Движок берётся у **приёмника**: выполняет дело он, один на все источники,
  /// и получить его нужно там, где заведомо умеют принимать. У источника его
  /// может не быть вовсе — это не мешает копировать из него.
  static Operation<OperationInputs, void> _transfer({required bool moves}) =>
      TaskOperation<OperationInputs, void>((op, inputs) async {
        final destination = inputs.destination;
        if (destination == null) {
          throw const FsError('', FsErrorKind.notSupported);
        }
        await op.delegate(
          moves ? inputs.editor.move() : inputs.editor.copy(),
          TransferParams(
            inputs.targets,
            destination,
            followLinks: inputs.option<bool>(FileOperations.followLinks) ?? false,
          ),
        );
      });
}
