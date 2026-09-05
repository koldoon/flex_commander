import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Иконка типа объекта.
///
/// Что показать, панель больше не решает: она спрашивает службу иконок
/// (`docs/spec/file-icons.md`), а та проходит правила — глиф, картинка с диска,
/// значок системы. Службы нет — рисуется встроенный хвост, те же глифы
/// FontAwesome, что и всегда.
///
/// У обычного файла иконки нет, но место под неё резервируется: в референсе для
/// этого рисовали невидимый кружок (`fa_circle_o`), чтобы имена всех строк
/// начинались с одной позиции. Здесь то же самое, только пустым местом той же
/// ширины.
class FileTypeIcon extends StatefulWidget {
  const FileTypeIcon({super.key, required this.entry, required this.selected, this.contentOf});

  final FileEntry entry;

  /// Строка под курсором: глиф перекрашивается в цвет текста курсора.
  ///
  /// Картинка — нет. Перекрасить цветной значок приложения значило бы стереть
  /// то единственное, ради чего его показывают, — ровно тогда, когда на строку
  /// смотрят.
  final bool selected;

  /// Чем открыть байты строки — для правил по содержимому.
  ///
  /// Ровно одно умение, а не панель целиком: строке от панели больше ничего не
  /// нужно, а чем меньше она о ней знает, тем проще будет другому виду списка.
  final Content Function(FileEntry entry)? contentOf;

  @override
  State<FileTypeIcon> createState() => _FileTypeIconState();
}

class _FileTypeIconState extends State<FileTypeIcon> {
  /// Чем рисуем сейчас. Ответ есть всегда — просто он бывает не окончательным.
  FileIcon _icon = const IconNothing();

  /// Для чего этот ответ получен: строка, размер и множитель экрана.
  ///
  /// Строки списка переиспользуются при прокрутке — один и тот же `State`
  /// достаётся то одному файлу, то другому, — и без этого ключа иконка уехала
  /// бы вместе с ним не на ту строку.
  String _resolvedFor = '';

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final icons = AppScope.read(context).fileIcons;
    final size = FileIconSize.of(theme.metrics, icons);

    _resolve(context, icons, size);
    return _draw(theme, size);
  }

  void _resolve(BuildContext context, FileIcons? icons, double size) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final key = '${widget.entry.path}|${widget.entry.size}|$size|$ratio';
    if (key == _resolvedFor) {
      return;
    }
    _resolvedFor = key;

    if (icons == null) {
      _icon = FileIcon.builtIn(widget.entry);
      return;
    }

    final open = widget.contentOf;
    final answer = icons.resolve(
      widget.entry,
      // Значок системы отрисуется под тот экран, на котором его покажут:
      // на Retina 13-точечная иконка должна приехать двадцатью шестью
      // пикселями, иначе её растянут вдвое.
      pixels: (size * ratio).round(),
      open: open == null ? null : () => open(widget.entry),
      stillWanted: () => mounted,
    );

    _icon = answer.now;
    answer.later?.then((icon) {
      // Строка могла уехать с экрана или достаться другому файлу, пока ответ
      // ехал: тогда он уже не про неё.
      if (mounted && key == _resolvedFor) {
        setState(() => _icon = icon);
      }
    });
  }

  Widget _draw(FcTheme theme, double size) => switch (_icon) {
    IconRole(:final role) => _glyph(theme, theme.icons.byRole(role), size),
    // Анализатор предлагает сделать `IconData` константой — но именно этого мы
    // и не хотим: и код, и шрифт известны только во время работы.
    // ignore: non_const_argument_for_const_parameter
    IconGlyph(:final codePoint) => _glyph(theme, IconData(codePoint, fontFamily: theme.icons.fontFamily), size),
    // Картинка рисуется как есть, без перекраски — см. [FileTypeIcon.selected].
    IconPicture(:final image) => Image(
      image: image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
    IconNothing() => SizedBox(width: size),
  };

  /// Глиф красится темой. Незнакомая роль не рисует ничего и не роняет
  /// приложение: имя роли приезжает из файла настроек, а его правят руками.
  Widget _glyph(FcTheme theme, IconData? data, double size) {
    if (data == null) {
      return SizedBox(width: size);
    }
    return Icon(data, size: size, color: widget.selected ? theme.colors.iconSelected : theme.colors.icon);
  }
}
