import 'fs_node.dart';
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
  const TransferParams(this.nodes, this.destination, {this.followLinks = false});

  final List<FsNode> nodes;
  final DirectoryNode destination;

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка переносится
  /// ссылкой, как в mc.
  final bool followLinks;
}

/// Что удалять и куда — в корзину или совсем.
class RemoveParams {
  const RemoveParams(this.nodes, {this.toTrash = true});

  final List<FsNode> nodes;
  final bool toTrash;
}

/// Где и под каким именем создать каталог.
class MakeDirectoryParams {
  const MakeDirectoryParams(this.parent, this.name);

  final DirectoryNode parent;
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
