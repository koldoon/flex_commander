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
  DialogState({this.width = 0, this.height = 0});

  /// Размер, заданный человеком; ноль по любой из сторон — не задан вовсе, и
  /// сторону считает рама.
  ///
  /// Не `Size` и не `null`: `Serializable` устроен вокруг словаря, а значение
  /// должно дописываться в готовый объект — чего в файле нет, остаётся как
  /// было.
  double width;
  double height;

  bool get hasWidth => width > 0 && width.isFinite;

  bool get hasHeight => height > 0 && height.isFinite;

  /// Помнить нечего: окно ни разу не тянули или размер сбросили.
  bool get isEmpty => !hasWidth && !hasHeight;

  @override
  void toMap(Map<String, dynamic> m) {
    if (hasWidth) {
      m['width'] = width;
    }
    if (hasHeight) {
      m['height'] = height;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    width = _sane(extract(width, m['width']));
    height = _sane(extract(height, m['height']));
  }

  /// Мусор вместо числа — то же, что «не задано»: окно откроется в любом
  /// случае, и пределы ему назначит рама.
  static double _sane(double value) => value.isFinite && value > 0 ? value : 0;

  @override
  bool operator ==(Object other) => other is DialogState && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'DialogState(${hasWidth ? width : '—'}×${hasHeight ? height : '—'})';
}
