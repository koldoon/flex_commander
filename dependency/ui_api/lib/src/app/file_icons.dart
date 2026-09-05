import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_metrics.dart';

/// Чем рисовать иконку строки — уже выбранное, но ещё не нарисованное.
///
/// Роль и код глифа остаются здесь **именем и числом**, а не `IconData`: во
/// что их превратить, знает тот, кто рисует, — у него под рукой тема. Служба
/// же решает, **какую** иконку показать, и о шрифтах ничего знать не обязана.
sealed class FileIcon {
  const FileIcon();

  /// Чем панель рисовала иконки до всяких правил.
  ///
  /// Живёт здесь, а не в модуле правил, потому что нужен обоим: модуль ставит
  /// это последним, встроенным хвостом списка, а панель без модуля рисует этим
  /// и только этим. Две копии пяти условий были бы двумя местами, где чинить
  /// одну и ту же ошибку.
  ///
  /// Порядок менять нельзя: битое узнаётся раньше каталога, иначе битый
  /// каталог покажется целым.
  static FileIcon builtIn(FileEntry entry) {
    if (entry.isParent) {
      return const IconRole('folder');
    }
    if (entry.broken) {
      return const IconRole('exclamation');
    }
    if (entry.isDirectory) {
      return const IconRole('folder');
    }
    if (entry.isLink) {
      return const IconRole('link');
    }
    if (entry.executable) {
      return const IconRole('asterisk');
    }
    return const IconNothing();
  }
}

/// Роль темы: `FcIcons.folder`, `link`, `asterisk`. Красится темой.
class IconRole extends FileIcon {
  const IconRole(this.role);

  final String role;
}

/// Глиф шрифта иконок темы по коду. Красится темой.
class IconGlyph extends FileIcon {
  const IconGlyph(this.codePoint);

  final int codePoint;
}

/// Картинка: своя с диска или значок системы.
///
/// **Перекраске не подлежит**, в том числе под курсором: перекрасить цветной
/// значок приложения в цвет текста курсора значило бы стереть то единственное,
/// ради чего его показывают, — ровно тогда, когда на строку смотрят.
class IconPicture extends FileIcon {
  const IconPicture(this.image);

  final ImageProvider image;
}

/// Иконки нет, но место под неё есть: так выглядит обычный файл сегодня.
class IconNothing extends FileIcon {
  const IconNothing();
}

/// Чем рисуется иконка строки.
///
/// Спецификация — `docs/spec/file-icons.md`.
abstract interface class FileIcons {
  /// Размер иконки в точках; `0` — как в теме.
  ///
  /// Отсюда же считаются высота строки и ширина колонки иконки: величина одна,
  /// и знать её должны все трое.
  double get size;

  /// Чем рисовать эту строку.
  ///
  /// Ответ есть **всегда и сразу** — просто он может быть не окончательным.
  /// Правило, которому нужно ещё не известное (тип по содержимому, значок
  /// системы), не совпадает, и проверка идёт дальше по списку; когда
  /// недостающее приезжает, список проверяется заново **с начала**, и ответ
  /// приходит в `later`.
  ///
  /// `later` null — уточнять нечего, строка нарисована окончательно.
  ///
  /// [open] даёт байты для условия по содержимому: строка принадлежит панели,
  /// и байты у неё берутся `panel.contentOf`. [pixels] — сторона иконки **в
  /// пикселях экрана**: значок системы отрисуется под тот экран, на котором
  /// его покажут, а сколько это в пикселях, знает тот, кто рисует, — у него и
  /// размер, и множитель. [stillWanted] спрашивают перед тем, как что-то
  /// читать: строка, уехавшая с экрана, ни байтов не читает, ни значка не
  /// просит.
  ({FileIcon now, Future<FileIcon>? later}) resolve(
    FileEntry entry, {
    required int pixels,
    Content Function()? open,
    bool Function()? stillWanted,
  });
}

/// Размер иконки — величина, которую должны знать трое: сама иконка, высота
/// строки и ширина колонки под ней.
///
/// Считается в одном месте именно поэтому: разойдись они, и иконка вылезет из
/// строки или в колонке останется дыра.
abstract final class FileIconSize {
  /// Больше этого иконка спорит со строкой, а не помогает ей.
  static const double max = 32;

  /// Настройка, если задана, иначе величина темы.
  static double of(FcMetrics metrics, FileIcons? icons) {
    final size = icons?.size ?? 0;
    return size <= 0 ? metrics.iconSize : size.clamp(metrics.iconSize, max);
  }

  /// Высота строки: не ниже обычной, а выше — с тем же просветом, что у глифа.
  static double rowHeight(FcMetrics metrics, double iconSize) {
    final grown = iconSize + (metrics.rowHeight - metrics.iconSize);
    return grown > metrics.rowHeight ? grown : metrics.rowHeight;
  }

  /// Ширина колонки иконки: отступ слева, сама иконка и просвет до имени
  /// **минус** поле ячейки имени — оно часть того же просвета.
  ///
  /// Считается, а не берётся из раскладки. Раньше там стояла константа 28, и
  /// `iconColumnWidth` объяснял, откуда она взялась, но ни на что не влиял:
  /// покрути `iconGap` — и в окне не менялось ничего. Метрика, которую нельзя
  /// подвигать, — это не метрика, а комментарий.
  static double columnWidth(FcMetrics metrics, double iconSize) =>
      metrics.iconLeftPadding + iconSize + metrics.iconGap - metrics.cellPadding;
}
