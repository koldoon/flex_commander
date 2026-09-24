import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// План переименования: что покажет таблица и что уедет работе
/// (`docs/spec/multi-rename.md`, §4, §5 и §8).
void main() {
  const naming = ReferenceFileNaming();

  FileEntry file(String name, {String directory = '/home', DateTime? modified}) => FileEntry(
    name: name,
    kind: EntryKind.file,
    path: '$directory/$name',
    directoryPath: directory,
    modified: modified,
  );

  RenamePlan planOf(
    List<FileEntry> entries,
    RenameSpec spec, {
    Map<String, Set<String>> taken = const {},
    FileNaming rule = naming,
  }) => RenamePlan.build(entries, spec, naming: rule, taken: taken);

  List<String> namesOf(RenamePlan plan) => [for (final row in plan.rows) row.to];

  group('порядок применения', () {
    test('маски имени и расширения складываются в имя', () {
      final plan = planOf([file('IMG_0041.JPG')], const RenameSpec(nameMask: 'Отпуск_[N5-]', extensionMask: 'jpg'));

      expect(namesOf(plan), ['Отпуск_0041.jpg']);
    });

    test('замена идёт по всему имени, а не по основе', () {
      final plan = planOf([file('IMG_0041.JPG')], const RenameSpec(find: '_0041.JPG', replace: '.jpg'));

      expect(namesOf(plan), ['IMG.jpg']);
    });

    test('регистр — свой у имени и свой у расширения', () {
      // Самое частое желание: `.JPG` → `.jpg`, не трогая имени.
      final plan = planOf([file('Отчёт.PDF')], const RenameSpec(extensionCase: RenameCase.lower));

      expect(namesOf(plan), ['Отчёт.pdf']);
    });

    test('составное расширение разбирает служба имён', () {
      final compound = _CompoundNaming();
      final plan = planOf([file('архив.tar.gz')], const RenameSpec(nameMask: '[N]-2026'), rule: compound);

      expect(namesOf(plan), ['архив-2026.tar.gz']);
    });

    test('пробелы по краям срезаются', () {
      final plan = planOf([file('отчёт.txt')], const RenameSpec(nameMask: '  [N]  '));

      expect(namesOf(plan), ['отчёт.txt']);
    });
  });

  group('счётчик', () {
    test('нумерует в порядке списка', () {
      final plan = planOf([
        file('b.txt'),
        file('a.txt'),
        file('c.txt'),
      ], const RenameSpec(nameMask: 'файл[C]', counter: RenameCounter(digits: 2)));

      expect(namesOf(plan), ['файл01.txt', 'файл02.txt', 'файл03.txt']);
    });
  });

  group('столкновения', () {
    test('два одинаковых новых имени помечают обе строки', () {
      final plan = planOf([file('a.txt'), file('b.txt')], const RenameSpec(nameMask: 'один'));

      expect(plan.rows.map((row) => row.status), everyElement(RenameStatus.duplicate));
      expect(plan.hasCollisions, isTrue);
      expect(plan.renames, isEmpty, reason: 'спорное работе не отдаётся');
    });

    test('занятое имя — только когда занявший не из набора', () {
      final plan = planOf(
        [file('a.txt')],
        const RenameSpec(nameMask: 'сосед'),
        taken: {
          '/home': {'сосед.txt'},
        },
      );

      expect(plan.rows.single.status, RenameStatus.taken);
    });

    test('имя, занятое тем, кто сам уезжает, — это порядок, а не спор', () {
      // `a → b`, `b → c`: имя `b` освободится, и работа сама выстроит порядок.
      final plan = planOf(
        [file('a.txt'), file('b.txt')],
        const RenameSpec(find: 'a', replace: 'b'),
        taken: {
          '/home': {'a.txt', 'b.txt'},
        },
      );

      expect(plan.rows.first.to, 'b.txt');
      expect(plan.rows.first.status, RenameStatus.renamed, reason: 'b.txt уезжает сам');
    });

    test('смена регистра одного файла спором не считается', () {
      final plan = planOf(
        [file('readme.md')],
        const RenameSpec(nameCase: RenameCase.upper),
        taken: {
          '/home': {'readme.md'},
        },
      );

      expect(plan.rows.single.to, 'README.md');
      expect(plan.rows.single.status, RenameStatus.renamed);
    });

    test('цели из разных каталогов не спорят', () {
      final plan = planOf([
        file('a.txt', directory: '/home'),
        file('a.txt', directory: '/other'),
      ], const RenameSpec(nameMask: 'один'));

      expect(plan.hasCollisions, isFalse);
      expect(plan.renames.length, 2);
    });
  });

  group('что уедет работе', () {
    test('только меняющиеся строки', () {
      final plan = planOf([file('a.txt'), file('b.txt')], const RenameSpec(find: 'a', replace: 'z'));

      expect(plan.changes, 1);
      expect(plan.renames, {'/home/a.txt': 'z.txt'});
    });

    test('негодная маска ничего не меняет и ничего не обещает', () {
      final plan = planOf([file('a.txt')], const RenameSpec(nameMask: '[N2-5'));

      expect(plan.renames, isEmpty);
      expect(namesOf(plan), ['a.txt']);
    });
  });

  group('набор переживает запись', () {
    test('поля возвращаются теми же', () {
      const spec = RenameSpec(
        nameMask: '[N]_[C]',
        extensionMask: 'bak',
        find: 'a',
        replace: 'b',
        regexp: true,
        caseSensitive: true,
        nameCase: RenameCase.upper,
        extensionCase: RenameCase.lower,
        counter: RenameCounter(start: 5, step: 2, digits: 3),
        byCreated: true,
      );

      final back = RenameSpec.fromMap(spec.toMap());

      expect(back.toMap(), spec.toMap());
    });
  });
}

/// Служба имён со словарём составных расширений — как в приложении.
class _CompoundNaming implements FileNaming {
  @override
  ({String base, String extension}) split(String name) {
    if (name.toLowerCase().endsWith('.tar.gz')) {
      return (base: name.substring(0, name.length - 7), extension: name.substring(name.length - 6));
    }
    return const ReferenceFileNaming().split(name);
  }
}
