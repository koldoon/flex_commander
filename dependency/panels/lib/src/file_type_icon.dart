import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Иконка типа объекта — глифами FontAwesome, как в референсе.
///
/// У обычного файла иконки нет, но место под неё резервируется: в референсе для
/// этого рисовали невидимый кружок (`fa_circle_o`), чтобы имена всех строк
/// начинались с одной позиции. Здесь то же самое, только пустым местом той же
/// ширины.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.entry, required this.selected});

  final FileEntry entry;

  /// Строка под курсором: иконка перекрашивается в цвет текста курсора.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final icon = _iconFor(entry, theme.icons);
    if (icon == null) {
      return SizedBox(width: theme.metrics.iconSize);
    }

    return Icon(icon, size: theme.metrics.iconSize, color: selected ? theme.colors.iconSelected : theme.colors.icon);
  }

  IconData? _iconFor(FileEntry entry, FcIcons icons) {
    if (entry.isParent) {
      return icons.folder;
    }
    if (entry.broken) {
      return icons.exclamation;
    }
    if (entry.isDirectory) {
      return icons.folder;
    }
    if (entry.isLink) {
      return icons.link;
    }
    if (entry.executable) {
      return icons.asterisk;
    }
    return null;
  }
}
