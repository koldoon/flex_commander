import 'package:fc_attributes/fc_attributes.dart';
import 'package:fc_attributes/src/mode_edit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Свёртка правки: то, ради чего режим едет парой масок, а не числом.
void main() {
  group('сведение нескольких объектов', () {
    test('совпавший бит определён, расходящийся — не трогать', () {
      // `644` и `600`: чтение владельцем совпало, чтение группой — нет.
      final edit = ModeEdit.of([0x1A4, 0x180]);

      expect(edit.valueOf(ModeBits.ownerRead), isTrue);
      expect(edit.valueOf(ModeBits.ownerWrite), isTrue);
      expect(edit.valueOf(ModeBits.groupRead), isNull, reason: 'у одного есть, у другого нет');
      expect(edit.valueOf(ModeBits.otherRead), isNull);
      expect(edit.valueOf(ModeBits.ownerExecute), isFalse, reason: 'нет у обоих');
    });

    test('один объект определяет все двенадцать битов', () {
      final edit = ModeEdit.of([0x1A4]);

      expect(edit.octal, 0x1A4);
      for (final bit in ModeBits.all) {
        expect(edit.valueOf(bit), isNotNull, reason: 'бит ${bit.toRadixString(8)}');
      }
    });

    test('пустой набор ничего не трогает', () {
      expect(ModeEdit.of(const []).isEmpty, isTrue);
    });
  });

  group('правка бита', () {
    test('тронутый попадает ровно в одну маску', () {
      final edit = ModeEdit.of([0x1A4, 0x180]);
      edit.set(ModeBits.groupRead, true);

      expect(edit.setBits & ModeBits.groupRead, isNonZero);
      expect(edit.clearBits & ModeBits.groupRead, isZero);
    });

    test('возврат в «не трогать» убирает из обеих', () {
      final edit = ModeEdit.of([0x1A4]);
      edit.set(ModeBits.ownerWrite, null);

      expect(edit.valueOf(ModeBits.ownerWrite), isNull);
      expect(edit.setBits & ModeBits.ownerWrite, isZero);
      expect(edit.clearBits & ModeBits.ownerWrite, isZero);
    });

    test('нетронутый в маски не попадает', () {
      final edit = ModeEdit.of([0x1A4, 0x180]);
      edit.set(ModeBits.groupRead, true);

      // «У выбранных по-разному» осталось «по-разному» — и у каждого объекта
      // этот бит останется своим.
      expect(edit.setBits & ModeBits.otherRead, isZero);
      expect(edit.clearBits & ModeBits.otherRead, isZero);
    });
  });

  group('что уедет работе', () {
    test('нетронутое не уезжает вовсе', () {
      final initial = ModeEdit.of([0x1A4]);
      final now = ModeEdit.of([0x1A4]);

      // У одного объекта исходно определены все двенадцать битов. Послать их
      // целиком значило бы назначить режим, который и так стоит.
      final changes = now.changesFrom(initial);
      expect(changes.setBits, 0);
      expect(changes.clearBits, 0);
    });

    test('уезжает ровно тронутый бит', () {
      final initial = ModeEdit.of([0x1A4]);
      final now = ModeEdit.of([0x1A4])..set(ModeBits.groupWrite, true);

      final changes = now.changesFrom(initial);
      expect(changes.setBits, ModeBits.groupWrite);
      expect(changes.clearBits, 0);
    });

    test('возврат в «не трогать» изменением не считается', () {
      final initial = ModeEdit.of([0x1A4]);
      final now = ModeEdit.of([0x1A4])..set(ModeBits.ownerRead, null);

      final changes = now.changesFrom(initial);
      expect(changes.setBits, 0);
      expect(changes.clearBits, 0);
    });

    test('из смешанного в определённое — уезжает', () {
      final initial = ModeEdit.of([0x1A4, 0x180]);
      final now = ModeEdit.of([0x1A4, 0x180])..set(ModeBits.groupRead, false);

      final changes = now.changesFrom(initial);
      expect(changes.clearBits, ModeBits.groupRead);
      expect(changes.setBits, 0);
    });
  });

  group('восьмеричное поле', () {
    test('и сетка флажков дают одни и те же маски', () {
      final typed = ModeEdit()..setOctal(0x1ED); // 0755
      final grid = ModeEdit.of([0x1ED]);

      expect(typed.setBits, grid.setBits);
      expect(typed.clearBits, grid.clearBits);
    });

    test('пока хоть один бит не тронут, числа нет', () {
      expect(ModeEdit.of([0x1A4, 0x180]).octal, isNull);
    });

    test('набранное покрывает все двенадцать битов', () {
      final edit = ModeEdit()..setOctal(0x1A4);

      expect((edit.setBits | edit.clearBits) & AttributeEdits.modeMask, AttributeEdits.modeMask);
      expect(edit.octal, 0x1A4);
      expect(edit.valueOf(ModeBits.setUid), isFalse);
    });
  });

  group('применение к режиму', () {
    test('поднимает названное и опускает названное', () {
      const edits = AttributeEdits(setBits: 0x020, clearBits: 0x002);

      expect(edits.applyToMode(0x1A4), 0x1A4 | 0x020);
    });

    test('нетронутый бит у каждого остаётся своим', () {
      const edits = AttributeEdits(setBits: 0x020);

      // Один объект исполняемый, другой нет — и таким каждый и останется.
      expect(edits.applyToMode(0x1ED) & 0x040, isNonZero);
      expect(edits.applyToMode(0x1A4) & 0x040, isZero);
    });

    test('тип объекта из старших битов не трогается', () {
      const edits = AttributeEdits(setBits: 0xFFF, clearBits: 0);

      // `0x41ED` — каталог с правами 755: каталогом он и остаётся.
      expect(edits.applyToMode(0x41ED) & ~AttributeEdits.modeMask, 0x4000);
    });
  });

  group('отбор по виду объекта', () {
    test('«всё подряд» берёт и файлы, и каталоги', () {
      const edits = AttributeEdits();

      expect(edits.reaches(isDirectory: true), isTrue);
      expect(edits.reaches(isDirectory: false), isTrue);
    });

    test('«только файлы» каталогов не трогает', () {
      const edits = AttributeEdits(applyTo: AttributeScope.files);

      expect(edits.reaches(isDirectory: false), isTrue);
      expect(edits.reaches(isDirectory: true), isFalse);
    });

    test('незнакомое имя отбора читается как «всё подряд»', () {
      // Доводы приезжают картой, и заявку может собрать кто угодно.
      expect(AttributeScope.byName('всякое'), AttributeScope.all);
      expect(AttributeScope.byName(null), AttributeScope.all);
    });
  });

  group('доводы работы', () {
    test('пустая правка не везёт ничего', () {
      expect(const AttributeEdits().toOptions(), isEmpty);
      expect(const AttributeEdits().isEmpty, isTrue);
    });

    test('туда и обратно — то же самое', () {
      final edits = AttributeEdits(
        setBits: 0x020,
        clearBits: 0x002,
        modified: DateTime.fromMillisecondsSinceEpoch(1600000000000),
        uid: 501,
        gid: 20,
        xattrSet: const {
          'com.example.note': [1, 0, 2],
        },
        xattrRemove: const ['com.apple.quarantine'],
        recursive: true,
        applyTo: AttributeScope.files,
      );

      final back = AttributeEdits.fromOptions(edits.toOptions());

      expect(back.setBits, 0x020);
      expect(back.clearBits, 0x002);
      expect(back.modified!.isAtSameMomentAs(edits.modified!), isTrue);
      expect(back.accessed, isNull);
      expect(back.uid, 501);
      expect(back.gid, 20);
      expect(back.xattrSet['com.example.note'], [1, 0, 2]);
      expect(back.xattrRemove, ['com.apple.quarantine']);
      expect(back.recursive, isTrue);
      expect(back.applyTo, AttributeScope.files);
    });

    test('имя ездит туда и обратно, не смешиваясь с числом', () {
      const named = AttributeEdits(owner: 'koldoon', group: 'staff');
      final back = AttributeEdits.fromOptions(named.toOptions());

      expect(back.owner, 'koldoon');
      expect(back.group, 'staff');
      // Одновременно число и имя не приходят никогда: окно шлёт что-то одно.
      expect(back.uid, isNull);
      expect(back.gid, isNull);
    });

    test('одного имени хватает, чтобы правка не была пустой', () {
      expect(const AttributeEdits(owner: 'koldoon').isEmpty, isFalse);
      expect(const AttributeEdits(group: 'staff').isEmpty, isFalse);
      expect(const AttributeEdits().isEmpty, isTrue);
    });

    test('чужое и негодное пропускается, а не роняет работу', () {
      final back = AttributeEdits.fromOptions(const {
        'setBits': 'не число',
        'recursive': 'да',
        'xattrRemove': ['имя', 7],
        'чужое': 42,
      });

      expect(back.setBits, 0);
      expect(back.recursive, isFalse);
      expect(back.xattrRemove, ['имя']);
    });

    test('дата уезжает числом: у той стороны свой часовой пояс', () {
      final at = DateTime.utc(2020, 1, 2, 3, 4, 5);
      final options = AttributeEdits(modified: at).toOptions();

      expect(options['modified'], at.millisecondsSinceEpoch);
      // Тот же миг, а не та же запись: обратно он приходит местным временем, и
      // это правильно — часовой пояс дело показа, а не границы.
      expect(AttributeEdits.fromOptions(options).modified!.isAtSameMomentAs(at), isTrue);
    });
  });
}
