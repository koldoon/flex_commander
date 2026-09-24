import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Настройки видов панели.
///
/// Общие на приложение, а не на панель: две панели с разным числом колонок в
/// кратком виде выглядели бы поломкой, а не настройкой
/// (`docs/spec/panel-views.md`, §7).
/// Оповещает о правках **сама**: настройки видов правят в окне настроек, а
/// видно их в панели — и ждать, пока панель проснётся по другому поводу, значит
/// показывать человеку, что нажатие ни к чему не привело
/// (`docs/spec/name-trim.md`, §7).
///
/// Оповещает не всякая правка, а та, которую видно сразу и некому показать
/// иначе: ширину столбца и долю дерева правят прямой манипуляцией, и тот, кто
/// их правит, перерисовывается сам.
class PanelsSettings extends ChangeNotifier implements Serializable {
  PanelsSettings({
    this.briefColumns = autoColumns,
    this.treeSize = true,
    this.cursorHoldsPlace = true,
    this.treeShare = defaultTreeShare,
    this.iconTileSize = defaultIconTileSize,
    this.iconNameWidth = autoNameWidth,
    this.columnWidth = defaultColumnWidth,
    String nameTrim = trimEnd,
    int statusLines = defaultStatusLines,
  }) : _nameTrim = nameTrim,
       _statusLines = statusLines;

  /// Какую долю ширины занимает дерево в комбинированном виде.
  static const double defaultTreeShare = 1 / 3;
  static const double minTreeShare = 0.15;
  static const double maxTreeShare = 0.7;

  /// «Сколько влезет»: число столбцов краткого вида считается по самому
  /// длинному имени в каталоге.
  static const int autoColumns = 0;

  /// Больше восьми столбцов имён не читаются вовсе — это уже не список, а
  /// сетка обрубков.
  static const int maxColumns = 8;

  /// Сторона значка в плитке вида «Значки», в точках.
  ///
  /// Своя величина, а не размер значка в строке списка: тот ограничен высотой
  /// строки (`FileIconSize`), а плитке нужно и 128 (`docs/spec/file-icons.md`,
  /// §8).
  ///
  /// Умолчание 64: при нём читается и глиф, и будущая миниатюра, а на половине
  /// окна помещается полсотни плиток.
  static const int defaultIconTileSize = 64;
  static const int minIconTileSize = 16;

  /// Больше — уже не сетка, а две плитки на экран; да и системе пришлось бы
  /// рисовать значок в пол-экрана.
  static const int maxIconTileSize = 256;

  /// Что предлагается списком; всё прочее набирается числом
  /// (`docs/spec/panel-view-icons.md`, §7).
  static const List<int> iconTileSizes = [16, 32, 48, 64, 128];

  /// Сторожевое значение списка: «Своё». Законным размером ноль не бывает.
  static const int customIconTileSize = 0;

  /// Сторона значка в плитке сетки.
  int iconTileSize;

  /// Сколько места отведено имени в плитке, в точках.
  ///
  /// [autoNameWidth] — вдвое от стороны значка, в пределах 80…160 точек: мера
  /// считается от значка, а не от панели, иначе окно пошире делало бы плитки
  /// шире, а не многочисленнее (`docs/spec/panel-view-icons.md`, §3).
  int iconNameWidth;

  /// «Как значок»: ширину имени считает сам вид.
  static const int autoNameWidth = 0;

  /// Сторожевое значение списка: «Своё». Отрицательной ширины не бывает.
  static const int customNameWidth = -1;

  /// Уже этого имя — огрызок в три знака: договаривать его будет подсказка, а
  /// не сетка.
  static const int minNameWidth = 40;

  /// Шире — уже не сетка, а список с картинками.
  static const int maxNameWidth = 400;

  /// Что предлагается списком; всё прочее набирается числом.
  static const List<int> nameWidths = [80, 120, 160, 200, 240];

  /// Ширина **первого** столбца вида «Столбцы», в точках.
  ///
  /// Первого, а не всех: остальные наследуют ширину своего родителя, а
  /// подстроенную мышью держит сам вид — из пути её не вывести, и в настройках
  /// по числу на каждый посещённый каталог копился бы мусор
  /// (`docs/spec/panel-view-columns.md`, §8).
  ///
  /// В окно настроек не идёт: её правят прямой манипуляцией, а два места для
  /// одного числа расходятся (`docs/spec/panel-views.md`, §7).
  static const int defaultColumnWidth = 220;

  /// Уже — в столбце не остаётся имени; шире — в панель не помещается и двух.
  static const int minColumnWidth = 120;
  static const int maxColumnWidth = 480;

  /// Ширина первого столбца вида «Столбцы».
  int columnWidth;

  /// Сколько столбцов у краткого вида; [autoColumns] — сколько влезет.
  int briefColumns;

  /// Чем жертвовать в имени, которому не хватило ширины: концом или серединой
  /// (`docs/spec/name-trim.md`).
  ///
  /// Строкой, а не перечислением: на диске лежит слово, и переименование члена
  /// перечисления в коде не должно превращать чужую настройку в умолчание —
  /// тем же приёмом живёт «что делать по концу команды» у терминала.
  String get nameTrim => _nameTrim;
  String _nameTrim;

  set nameTrim(String value) {
    if (value == _nameTrim) {
      return;
    }
    _nameTrim = value;
    notifyListeners();
  }

  /// Отрезать хвост: `Отчёт за третий квартал 20…`. Так было всегда.
  static const String trimEnd = 'end';

  /// Вырезать середину: `Отчёт за третий…ный.xlsx`. Привычка Finder.
  static const String trimMiddle = 'middle';

  /// Удобство для тех, кто показывает имена: им нужно не слово, а сторона.
  bool get trimsNameInMiddle => nameTrim == trimMiddle;

  /// Сколько строчек позволено строке состояния
  /// (`docs/spec/panel-status-lines.md`).
  ///
  /// Одна: дёрганье списка под каждой стрелкой человек видит каждый раз, а
  /// недоговорённое имя — лишь когда оно длинное. Кому дороже обещание «имя
  /// договаривает полоса», тот ставит три.
  static const int defaultStatusLines = 1;
  static const int minStatusLines = 1;

  /// Больше трёх нельзя: четвёртая строчка отъедает от списка заметно, а имя,
  /// не влезшее в три, не влезет и в пять.
  static const int maxStatusLines = 3;

  int get statusLines => _statusLines;
  int _statusLines;

  set statusLines(int value) {
    final sane = value.clamp(minStatusLines, maxStatusLines);
    if (sane == _statusLines) {
      return;
    }
    _statusLines = sane;
    notifyListeners();
  }

  /// Показывать ли размер в дереве.
  ///
  /// Включено: размер — то, ради чего каталог и помечают
  /// (`docs/spec/panel-view-tree.md`, §4).
  bool treeSize;

  /// Держать строку под курсором на месте, когда список переставили.
  ///
  /// Включено: перестановку человек попросил, а вот терять из виду то, на что
  /// он смотрит, не просил (`docs/spec/panel-views.md`, §9). Выключенное
  /// возвращает прежнюю минимальную подмотку: список стоит, курсор уезжает.
  bool cursorHoldsPlace;

  /// Доля ширины под деревом в комбинированном виде.
  ///
  /// Правится перетаскиванием разделителя между столбцами
  /// (`docs/spec/panel-view-combined.md`, §7).
  double treeShare;

  @override
  void fromMap(Map<String, dynamic> m) {
    briefColumns = extract(briefColumns, m['briefColumns']).clamp(autoColumns, maxColumns);
    treeSize = extract(treeSize, m['treeSize']);
    cursorHoldsPlace = extract(cursorHoldsPlace, m['cursorHoldsPlace']);
    treeShare = extract(treeShare, m['treeShare']).clamp(minTreeShare, maxTreeShare);
    iconTileSize = extract(iconTileSize, m['iconTileSize']).clamp(minIconTileSize, maxIconTileSize);
    columnWidth = extract(columnWidth, m['columnWidth']).clamp(minColumnWidth, maxColumnWidth);
    // Незнакомое слово — это чужая настройка или опечатка в правленом руками
    // файле: показываем как было, а не гадаем.
    _statusLines = extract(statusLines, m['statusLines']).clamp(minStatusLines, maxStatusLines);
    final trim = extract(nameTrim, m['nameTrim']);
    _nameTrim = trim == trimMiddle ? trimMiddle : trimEnd;
    final width = extract(iconNameWidth, m['iconNameWidth']);
    iconNameWidth = width <= autoNameWidth ? autoNameWidth : width.clamp(minNameWidth, maxNameWidth);
    // Настройки перечитали целиком — скажем и об этом: так же приходит
    // выбранный набор настроек, и виды обязаны его увидеть.
    notifyListeners();
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['briefColumns'] = briefColumns;
    m['treeSize'] = treeSize;
    m['cursorHoldsPlace'] = cursorHoldsPlace;
    m['treeShare'] = treeShare;
    m['iconTileSize'] = iconTileSize;
    m['iconNameWidth'] = iconNameWidth;
    m['columnWidth'] = columnWidth;
    m['nameTrim'] = nameTrim;
    m['statusLines'] = statusLines;
  }
}
