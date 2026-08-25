import 'package:fc_api/fc_api.dart';

/// Виды состояний — реализация [Views].
///
/// Своих видов у ядра нет ни одного, как и видов содержимого панели: их
/// приносят модули. Ядро только находит, чем показать то, что ему дали.
class ViewRegistry implements Views {
  const ViewRegistry(this._builders);

  final Map<Type, StateViewBuilder<Object>> _builders;

  /// Типы, для которых вид объявлен.
  Iterable<Type> get types => _builders.keys;

  @override
  StateViewBuilder<Object>? builderFor(Type stateType) => _builders[stateType];
}

/// Ни одного вида.
///
/// Приложению без интерфейса — тесту состояния, сценарию — рисовать нечем и
/// незачем.
class NoViews implements Views {
  const NoViews();

  @override
  StateViewBuilder<Object>? builderFor(Type stateType) => null;
}
