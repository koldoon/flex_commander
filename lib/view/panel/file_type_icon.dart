import 'package:flutter/material.dart';

import '../../model/tree/fs_node.dart';
import '../theme/app_theme.dart';

/// Иконка типа объекта.
///
/// У обычного файла иконки нет — место под неё всё равно резервируется, чтобы
/// имена стояли в одну колонку (так же было в референсе).
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.node, required this.selected});

  final FsNode node;

  /// Строка под курсором: иконка перекрашивается в цвет текста курсора.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final data = _iconFor(node);
    if (data == null) {
      return SizedBox(width: theme.metrics.iconSize);
    }

    final (icon, color) = data;
    return Icon(icon, size: theme.metrics.iconSize, color: selected ? theme.colors.cursorText : color(theme));
  }

  (IconData, Color Function(FcTheme))? _iconFor(FsNode node) {
    if (node is ParentDirNode) {
      return (Icons.folder, (theme) => theme.colors.folderIcon);
    }
    if (node is FileNode && node.broken) {
      return (Icons.priority_high, (theme) => theme.colors.error);
    }
    if (node is DirectoryNode) {
      return (Icons.folder, (theme) => theme.colors.folderIcon);
    }
    if (node is LinkNode) {
      // Ссылка на каталог выглядит папкой со стрелкой: важно и то, куда она
      // ведёт, и то, что это ссылка.
      return node.isDirectoryLink
          ? (Icons.drive_file_move_outlined, (theme) => theme.colors.folderIcon)
          : (Icons.link, (theme) => theme.colors.secondaryText);
    }
    if (node is FileNode && node.executable) {
      return (Icons.chevron_right, (theme) => theme.colors.secondaryText);
    }
    return null;
  }
}
