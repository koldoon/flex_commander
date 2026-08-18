import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';

/// Иконка типа объекта — глифами FontAwesome, как в референсе.
///
/// У обычного файла иконки нет, но место под неё резервируется: в референсе для
/// этого рисовали невидимый кружок (`fa_circle_o`), чтобы имена всех строк
/// начинались с одной позиции. Здесь то же самое, только пустым местом той же
/// ширины.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.node, required this.selected});

  final FsNode node;

  /// Строка под курсором: иконка перекрашивается в цвет текста курсора.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final icon = _iconFor(node, theme.icons);
    if (icon == null) {
      return SizedBox(width: theme.metrics.iconSize);
    }

    return Icon(icon, size: theme.metrics.iconSize, color: selected ? theme.colors.iconSelected : theme.colors.icon);
  }

  IconData? _iconFor(FsNode node, FcIcons icons) {
    if (node is ParentDirNode) {
      return icons.folder;
    }
    if (node is FileNode && node.broken) {
      return icons.exclamation;
    }
    if (node is DirectoryNode) {
      return icons.folder;
    }
    if (node is LinkNode) {
      return icons.link;
    }
    if (node is FileNode && node.executable) {
      return icons.asterisk;
    }
    return null;
  }
}
