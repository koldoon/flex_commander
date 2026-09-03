import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';
import 'tree_provider.dart';

/// Что работа получает от ядра, когда её заводят.
///
/// Ядро уже развернуло имя набора в узлы и нашло каталог-приёмник: работа
/// получает **живое**, потому что живёт по эту сторону границы. Всё остальное
/// приехало значениями и лежит в [options] как есть.
class OperationInputs {
  const OperationInputs({
    required this.targets,
    required this.editor,
    this.destination,
    this.options = const {},
    this.onFound = _nothingFound,
  });

  /// Над чем работать — узлами. Псевдострока «..» сюда не попадает: ядро
  /// отсеивает её, разворачивая набор.
  final List<FsNode> targets;

  /// Куда — узлом каталога; null, если работе приёмник не нужен.
  final DirectoryNode? destination;

  /// Движок файловых операций: обход, конфликты, ход дела — общие для всех
  /// источников.
  final TreeEditor editor;

  /// Доводы, приехавшие в заявке.
  final Map<String, Object?> options;

  /// Куда работа складывает найденное — **по ходу дела**, а не в конце.
  ///
  /// Ради одной работы: поиск. У остальных ответ один — исход, и звать это
  /// некому. Тому же, кто ищет, ответ нужен по частям: на большом дереве
  /// первые попадания видны сразу, и обычно этого довольно, — а держать их до
  /// конца обхода значило бы показывать пустое окно всё время работы.
  ///
  /// Пачками, а не по одной: находки приходят быстрее, чем экран успевает
  /// обновиться.
  final void Function(List<FsNode> found) onFound;

  static void _nothingFound(List<FsNode> found) {}

  T? option<T>(String name) {
    final value = options[name];
    return value is T ? value : null;
  }
}

/// Как создать работу этого рода.
///
/// Фабрика зовётся на каждый запуск: у работы своё состояние исполнения,
/// и один экземпляр на всех не годится.
typedef OperationFactory = Operation<OperationInputs, void> Function(FcServices services);
