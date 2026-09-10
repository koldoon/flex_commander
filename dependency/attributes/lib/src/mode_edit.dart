import 'attribute_edits.dart';

/// Биты режима — те, что показывает сетка флажков.
///
/// Порядок тот же, что в строке `rwxrwxrwx`, плюс три особых бита сверху.
abstract final class ModeBits {
  static const int setUid = 0x800;
  static const int setGid = 0x400;
  static const int sticky = 0x200;

  static const int ownerRead = 0x100;
  static const int ownerWrite = 0x080;
  static const int ownerExecute = 0x040;

  static const int groupRead = 0x020;
  static const int groupWrite = 0x010;
  static const int groupExecute = 0x008;

  static const int otherRead = 0x004;
  static const int otherWrite = 0x002;
  static const int otherExecute = 0x001;

  /// Все двенадцать, сверху вниз.
  static const List<int> all = [
    setUid,
    setGid,
    sticky,
    ownerRead,
    ownerWrite,
    ownerExecute,
    groupRead,
    groupWrite,
    groupExecute,
    otherRead,
    otherWrite,
    otherExecute,
  ];
}

/// Двенадцать битов режима, каждый в одном из трёх состояний.
///
/// Состояние выражено **не третьим полем у бита, а парой масок**: бит в
/// [setBits] — поднять, в [clearBits] — опустить, ни там ни там — не трогать.
/// В этом же виде правка и уезжает работе, поэтому переводить её из одного
/// представления в другое не приходится вовсе.
class ModeEdit {
  ModeEdit({this.setBits = 0, this.clearBits = 0});

  /// Свести несколько объектов в одно состояние.
  ///
  /// Совпавший у всех бит определён, расходящийся — «не трогать»: любое другое
  /// его положение соврало бы, а нажатие на соседний флажок молча выровняло бы
  /// его у всех.
  factory ModeEdit.of(Iterable<int> modes) {
    final list = modes.toList();
    if (list.isEmpty) {
      return ModeEdit();
    }
    var set = 0;
    var clear = 0;
    for (final bit in ModeBits.all) {
      final raised = list.map((mode) => mode & bit != 0).toSet();
      if (raised.length != 1) {
        continue;
      }
      if (raised.single) {
        set |= bit;
      } else {
        clear |= bit;
      }
    }
    return ModeEdit(setBits: set, clearBits: clear);
  }

  int setBits;
  int clearBits;

  /// Состояние бита: true — поднят, false — опущен, null — не трогать.
  bool? valueOf(int bit) {
    if (setBits & bit != 0) {
      return true;
    }
    if (clearBits & bit != 0) {
      return false;
    }
    return null;
  }

  void set(int bit, bool? value) {
    setBits &= ~bit;
    clearBits &= ~bit;
    if (value == true) {
      setBits |= bit;
    } else if (value == false) {
      clearBits |= bit;
    }
  }

  /// Восьмеричное значение — когда определены **все** двенадцать битов.
  ///
  /// Хоть один в «не трогать» — числа нет: показывать вместо него ноль значило
  /// бы предложить человеку выключить то, чего он не выбирал.
  int? get octal {
    if ((setBits | clearBits) & AttributeEdits.modeMask != AttributeEdits.modeMask) {
      return null;
    }
    return setBits & AttributeEdits.modeMask;
  }

  /// Набранное руками восьмеричное — частный случай той же пары масок: всё,
  /// чего в нём нет, опускается.
  void setOctal(int value) {
    setBits = value & AttributeEdits.modeMask;
    clearBits = AttributeEdits.modeMask & ~setBits;
  }

  /// Ничего не тронуто.
  bool get isEmpty => setBits == 0 && clearBits == 0;

  /// Что изменилось против исходного — только это и уедет работе.
  ///
  /// Не всё определённое: у одного объекта исходно определены **все**
  /// двенадцать битов, и посылать их целиком значило бы назначать режим,
  /// который и так стоит. «Apply», нажатый без единой правки, обязан не делать
  /// ничего — и здесь это выражено данными, а не проверкой в окне.
  ///
  /// Возврат бита в «не трогать» тоже изменением не считается: объект остаётся
  /// с тем, что у него было, а это и есть исходное.
  ({int setBits, int clearBits}) changesFrom(ModeEdit initial) {
    var set = 0;
    var clear = 0;
    for (final bit in ModeBits.all) {
      final now = valueOf(bit);
      if (now == null || now == initial.valueOf(bit)) {
        continue;
      }
      if (now) {
        set |= bit;
      } else {
        clear |= bit;
      }
    }
    return (setBits: set, clearBits: clear);
  }
}
