import 'fs_node.dart';
import 'tree_provider.dart';

/// Аренда смонтированного провайдера: пока её не отпустили, он жив.
///
/// Владелец смонтированного — не «тот, кто открыл», а **каждый, у кого на
/// руках аренда**. Правило «отпускает тот, кто уходит» держалось на модальном
/// окне операции: пока копирование идёт, панель никуда не уйдёт. Кнопка
/// «Background» это правило и сломала — работа продолжается, а панель свободна.
///
/// Отпускать полагается из `finally`, поэтому второй вызов [release] ничего не
/// делает: в `finally` попадают и по дороге ошибки, и после обычного конца.
abstract interface class ProviderLease {
  TreeProvider get provider;

  /// Отпускает. Последний ушедший закрывает провайдера.
  Future<void> release();
}

/// Узел вместе с арендой всего, что смонтировано ради него.
///
/// Разбор пути `/home/a.zip/inner/b.7z/x` монтирует двух провайдеров, и держатся
/// они не сами по себе: аренда внутреннего держит аренду внешнего, поэтому
/// арендатору достаётся одна — самая глубокая.
class ResolvedNode {
  const ResolvedNode(this.node, this.lease);

  /// Ничего не нашлось, и арендовать нечего.
  const ResolvedNode.none() : node = null, lease = null;

  final FsNode? node;

  /// null — узел лежит в общем корне: его никто не монтировал, и отпускать
  /// нечего.
  final ProviderLease? lease;

  Future<void> release() async => lease?.release();
}

/// Что смонтировано и сколько у него арендаторов.
///
/// Не отладочная роскошь: этим проверяется, что после работы ничего не
/// осталось, и этим же справка ответит на вопрос «почему архив занят».
class MountedProvider {
  const MountedProvider({required this.scheme, required this.host, required this.tenants, required this.opening});

  /// Схема, которой смонтировано: `zip`, `7z`, `ssh`.
  final String scheme;

  /// Над чем: путь узла-хозяина или адрес источника.
  final String host;

  /// Сколько арендаторов держат его прямо сейчас.
  final int tenants;

  /// Ещё открывается: арендаторы уже есть, а провайдера ещё нет.
  final bool opening;

  @override
  String toString() => '$scheme over $host: $tenants tenant(s)${opening ? ', opening' : ''}';
}
