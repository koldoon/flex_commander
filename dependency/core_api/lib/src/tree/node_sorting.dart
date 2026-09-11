import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';

/// Как сравнивают по колонке: меньше — выше в списке.
///
/// Сравнение живёт **у колонки**, а не в закрытом перечислении случаев: его
/// приносит тот же модуль, что объявил колонку (`BackendRegistry.column`), а
/// источник со своими колонками отдаёт своё (`PanelExtraColumns.comparatorOf`).
/// Добавить колонку — значит объявить её, а не править ядро
/// (`docs/spec/column-registry.md`, §5).
typedef NodeComparator = int Function(FsNode a, FsNode b);

/// Как модуль отдаёт сравнение своей колонки.
///
/// Фабрика, а не готовый компаратор: сравнению бывают нужны службы — колонке
/// расширения нужен `FileNaming`, а он собран из настроек и во время
/// объявления модуля ещё не существует. То же правило, что у всех фабрик
/// реестра: службы читают из них, а не при объявлении.
typedef ColumnComparatorFactory = NodeComparator Function(FcServices services);

/// Компаратор для правила сортировки.
///
/// Само правило ([SortSpec]) — общее значение: его выбирают на экране и
/// сохраняют в настройках. Сравнение живёт здесь, где живут узлы.
///
/// Порядок проверок: псевдоузел «..» всегда первый, затем — каталоги перед
/// файлами, и только после этого сравнение по колонке. Первые два правила
/// не переворачиваются направлением сортировки.
///
/// [column] — сравнение колонки; null означает «сравнения нет»: так выходит с
/// колонкой, которой никто не объявил сравнения, и с той, которую не объявлял
/// вовсе никто. Тогда всё решает доводчик по имени. Общие правила и доводчик
/// остаются здесь при любом сравнении: без доводчика порядок «плавает» между
/// перечитываниями, а без «..» и каталогов список выглядит чужим.
int Function(FsNode, FsNode) comparatorFor(
  SortSpec spec, {
  FileNaming naming = const ReferenceFileNaming(),
  NodeComparator? column,
}) {
  return (a, b) {
    if (a is ParentDirNode) {
      return b is ParentDirNode ? 0 : -1;
    }
    if (b is ParentDirNode) {
      return 1;
    }

    if (spec.foldersFirst) {
      final aDir = _isDirectory(a);
      final bDir = _isDirectory(b);
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
    }

    var result = column == null ? 0 : column(a, b);
    if (result == 0) {
      // Доводчик по имени: без него порядок «плавает» между перечитываниями.
      result = naturalCompare(a.name, b.name);
    }
    return spec.direction == SortDirection.ascending ? result : -result;
  };
}

bool _isDirectory(FsNode node) => node is DirectoryNode || (node is LinkNode && node.isDirectoryLink);
