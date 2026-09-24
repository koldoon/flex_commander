import 'fs_node.dart';
import 'journal.dart';
import 'tree_provider.dart';

// Данные, с которыми заводят работы над деревом.
//
// Отдельным файлом, а не рядом с интерфейсами: это и есть граница «живое /
// снимок», и стеречь её проще, когда она в одном месте. Ни приложения, ни
// областей, ни панелей здесь быть не может — живое состояние читает команда, до
// запуска, а работа получает снимок. Проверяет это доктринальный тест
// (`operation_contract_test.dart`): фоновое копирование сломалось бы в тот
// день, когда панель вышла из архива, — работа пошла бы спрашивать «где мы
// сейчас» у того, кто уже ушёл.

/// Что читать: каталог и нужны ли в списке скрытые объекты.
class ListingParams {
  const ListingParams(this.dir, {this.includeHidden = false});

  final DirectoryNode dir;
  final bool includeHidden;
}

/// Что переносить и куда.
///
/// Отдельный тип, а не аргументы метода: работа заводится один раз, а
/// запускается тогда, когда до неё дойдёт очередь, — и всё это время снимок
/// должен где-то лежать. Живого состояния здесь нет и быть не может: ни
/// панели, ни областей, ни приложения.
class TransferParams {
  const TransferParams(this.nodes, this.destination, {this.followLinks = false, this.journal = Journal.none});

  final List<FsNode> nodes;
  final DirectoryNode destination;

  /// Куда писать сделанное; [Journal.none] — не писать
  /// (`docs/spec/operation-history.md`, §4).
  final Journal journal;

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка переносится
  /// ссылкой, как в mc.
  final bool followLinks;
}

/// Что удалять и куда — в корзину или совсем.
class RemoveParams {
  const RemoveParams(this.nodes, {this.toTrash = true, this.journal = Journal.none});

  final List<FsNode> nodes;
  final bool toTrash;

  /// Куда писать сделанное; [Journal.none] — не писать.
  final Journal journal;
}

/// Где и под каким именем создать каталог.
class MakeDirectoryParams {
  const MakeDirectoryParams(this.parent, this.name, {this.journal = Journal.none});

  final DirectoryNode parent;
  final String name;

  /// Куда писать сделанное; [Journal.none] — не писать.
  final Journal journal;
}

/// Что переименовать и во что.
class RenameParams {
  const RenameParams(this.node, this.name, {this.journal = Journal.none});

  final FsNode node;

  /// Куда писать сделанное; [Journal.none] — не писать.
  final Journal journal;

  /// Новое имя — только имя, без пути: переименование не переносит.
  final String name;
}

/// Что монтировать и над чем.
class AcquireParams {
  const AcquireParams(this.scheme, this.host);

  final String scheme;
  final FsNode host;
}

/// Что разбирать и с какого корня.
///
/// [from] — корень, с которого начинается разбор. У каждой панели он свой: одна
/// может стоять на локальной ФС, другая — на сервере.
class ResolvePathParams {
  const ResolvePathParams(this.path, {this.from});

  final String path;
  final TreeProvider? from;
}
