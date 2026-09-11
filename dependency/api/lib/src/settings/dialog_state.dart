import '../serialization.dart';

/// Что окно команды помнит о себе между запусками.
///
/// **Состояние окна, а не его размер.** Размер — первое, что понадобилось
/// запоминать, но вряд ли последнее: завтра это будет разложение колонок в
/// находках, послезавтра — открытая вкладка. Второе поле должно **добавляться**,
/// а не переименовывать всё вокруг, а имена здесь — внешний контракт: они лежат
/// в `settings.json` (`docs/spec/dialog-resize.md`, §3).
///
/// Живёт рядом с геометрией главного окна, шириной колонок и долей
/// разделителя: всё это одного рода — вид приложения между запусками.
class DialogState implements Serializable {
  DialogState({this.width = 0, this.height = 0, this.offsetX = 0, this.offsetY = 0});

  /// Размер, заданный человеком; ноль по любой из сторон — не задан вовсе, и
  /// сторону считает рама.
  ///
  /// Не `Size` и не `null`: `Serializable` устроен вокруг словаря, а значение
  /// должно дописываться в готовый объект — чего в файле нет, остаётся как
  /// было.
  double width;
  double height;

  /// Куда окно отодвинули от места, которое назначила бы рама.
  ///
  /// **Смещение, а не место.** Место считается от области, над которой окно
  /// стоит, и от размера окна приложения (`docs/spec/dialog-placement.md`,
  /// §3) — а они меняются: приложение сузили, панель перетащили. Точка,
  /// записанная числом, после этого означала бы уже не то, где окно
  /// оставили; смещение переживает и то и другое.
  ///
  /// Ноль по обеим сторонам — окно не двигали, и стоит оно там, где положено.
  /// Отрицательное — влево и вверх: растянутое за верхний край окно уезжает
  /// вверх именно так (`docs/spec/dialog-resize.md`, §6).
  double offsetX;
  double offsetY;

  bool get hasWidth => width > 0 && width.isFinite;

  bool get hasHeight => height > 0 && height.isFinite;

  /// Окно отодвинули с назначенного места.
  bool get hasOffset => offsetX != 0 || offsetY != 0;

  /// Помнить нечего: окно ни разу не трогали или всё сбросили.
  bool get isEmpty => !hasWidth && !hasHeight && !hasOffset;

  @override
  void toMap(Map<String, dynamic> m) {
    if (hasWidth) {
      m['width'] = width;
    }
    if (hasHeight) {
      m['height'] = height;
    }
    // Ноль не пишется: «не отодвигали» — это отсутствие записи, а не число.
    if (offsetX != 0) {
      m['offsetX'] = offsetX;
    }
    if (offsetY != 0) {
      m['offsetY'] = offsetY;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    width = _sane(extract(width, m['width']));
    height = _sane(extract(height, m['height']));
    offsetX = _saneOffset(extract(offsetX, m['offsetX']));
    offsetY = _saneOffset(extract(offsetY, m['offsetY']));
  }

  /// Мусор вместо числа — то же, что «не задано»: окно откроется в любом
  /// случае, и пределы ему назначит рама.
  static double _sane(double value) => value.isFinite && value > 0 ? value : 0;

  /// У смещения годится и ноль, и отрицательное — негодна только бесконечность
  /// с не-числом: окно, уехавшее в никуда, не вернуть ничем.
  static double _saneOffset(double value) => value.isFinite ? value : 0;

  @override
  bool operator ==(Object other) =>
      other is DialogState &&
      other.width == width &&
      other.height == height &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(width, height, offsetX, offsetY);

  @override
  String toString() =>
      'DialogState(${hasWidth ? width : '—'}×${hasHeight ? height : '—'}'
      '${hasOffset ? ' @ $offsetX, $offsetY' : ''})';
}
