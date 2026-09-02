import 'package:fc_ui_api/fc_ui_api.dart';

/// Виды состояний — реализация [Views].
///
/// Своих видов у ядра нет ни одного, как и видов содержимого панели: их
/// приносят модули. Ядро только находит, чем показать то, что ему дали.
class ViewRegistry implements Views {
  const ViewRegistry(this._views);

  final Map<Type, StateView> _views;

  /// Типы, на которые вид объявлен.
  Iterable<Type> get types => _views.keys;

  @override
  StateViewBuilder<Object>? builderFor(Object state) {
    // Точное совпадение вперёд подходящего: вид, объявленный ровно на этот тип,
    // очевидно ближе к делу, чем вид на его интерфейс.
    final exact = _views[state.runtimeType];
    if (exact != null) {
      return exact.build;
    }

    final matching = [
      for (final view in _views.values)
        if (view.matches(state)) view,
    ];
    if (matching.length > 1) {
      final names = matching.map((view) => view.stateType).join(', ');
      throw StateError(
        'Состоянию ${state.runtimeType} подходит несколько видов ($names): выбор стал бы делом порядка модулей',
      );
    }
    return matching.isEmpty ? null : matching.single.build;
  }
}

/// Ни одного вида.
///
/// Приложению без интерфейса — тесту состояния, сценарию — рисовать нечем и
/// незачем.
class NoViews implements Views {
  const NoViews();

  @override
  StateViewBuilder<Object>? builderFor(Object state) => null;
}
