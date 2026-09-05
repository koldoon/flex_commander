import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

FileEntry entryOf({
  String name = 'main.dart',
  EntryKind kind = EntryKind.file,
  bool executable = false,
  bool broken = false,
  String scheme = 'fs',
}) => FileEntry(
  name: name,
  kind: kind,
  path: '$scheme:/tmp/$name',
  scheme: scheme,
  executable: executable,
  broken: broken,
);

void main() {
  group('Условие', () {
    test('без единого поля подходит любой строке', () {
      expect(EntryCondition().matches(entryOf()), isTrue);
      expect(EntryCondition().matches(entryOf(kind: EntryKind.directory)), isTrue);
    });

    test('незаданное не проверяется', () {
      // Задана только маска — про вид строки и флаги не спрашивают вовсе.
      final condition = EntryCondition(mask: '*.dart');
      expect(condition.matches(entryOf(kind: EntryKind.directory)), isTrue);
      expect(condition.matches(entryOf(name: 'main.py')), isFalse);
    });

    test('заданное складывается по «и», а не по «или»', () {
      final condition = EntryCondition(mask: '*.dart', executable: true);
      expect(condition.matches(entryOf(executable: true)), isTrue);
      expect(condition.matches(entryOf()), isFalse);
      expect(condition.matches(entryOf(name: 'run', executable: true)), isFalse);
    });

    test('вид строки — из набора', () {
      final condition = EntryCondition(kinds: {EntryKind.directory, EntryKind.link});
      expect(condition.matches(entryOf(kind: EntryKind.link)), isTrue);
      expect(condition.matches(entryOf()), isFalse);
    });

    test('скрытое — по имени, как и везде', () {
      final condition = EntryCondition(hidden: true);
      expect(condition.matches(entryOf(name: '.gitignore')), isTrue);
      expect(condition.matches(entryOf()), isFalse);
    });

    test('источник строки', () {
      expect(EntryCondition(scheme: 'zip').matches(entryOf(scheme: 'zip')), isTrue);
      expect(EntryCondition(scheme: 'zip').matches(entryOf()), isFalse);
    });
  });

  group('Условие о содержимом', () {
    test('о нём известно заранее', () {
      expect(EntryCondition(mask: '*').needsContent, isFalse);
      expect(EntryCondition(contentType: {'png'}).needsContent, isTrue);
      expect(EntryCondition(contentGroup: {'image'}).needsContent, isTrue);
    });

    test('без ответа о содержимом условие не подходит', () {
      final condition = EntryCondition(contentGroup: {'image'});
      expect(condition.matches(entryOf()), isFalse);
      expect(condition.matches(entryOf(), group: 'archive'), isFalse);
      expect(condition.matches(entryOf(), group: 'image'), isTrue);
    });

    test('тип и семья спрашиваются по отдельности', () {
      final condition = EntryCondition(contentType: {'png', 'jpeg'});
      expect(condition.matches(entryOf(), type: 'png', group: 'image'), isTrue);
      expect(condition.matches(entryOf(), type: 'gif', group: 'image'), isFalse);
    });
  });

  group('Разбор из настроек', () {
    test('туда и обратно', () {
      final source = {
        'mask': '*.dart;!*.g.dart',
        'kinds': ['file', 'link'],
        'hidden': false,
        'executable': true,
        'broken': false,
        'scheme': 'fs',
        'contentType': ['png'],
        'contentGroup': ['image'],
      };
      final json = EntryCondition.fromJson(source).toJson();

      expect(json['mask'], '*.dart;!*.g.dart');
      expect(json['kinds'], ['file', 'link']);
      expect(json['executable'], isTrue);
      expect(json['contentType'], ['png']);
      // Условие спрашивает и о содержимом — значит, без ответа о нём не
      // подойдёт даже строке, совпавшей всем остальным.
      expect(EntryCondition.fromJson(json).matches(entryOf(executable: true)), isFalse);
      expect(EntryCondition.fromJson(json).matches(entryOf(executable: true), type: 'png', group: 'image'), isTrue);
    });

    test('одно имя вместо списка', () {
      final condition = EntryCondition.fromJson({'kinds': 'directory'});
      expect(condition.matches(entryOf(kind: EntryKind.directory)), isTrue);
      expect(condition.matches(entryOf()), isFalse);
    });

    test('пустая запись — условие, подходящее всем', () {
      expect(EntryCondition.fromJson(const {}).matches(entryOf()), isTrue);
    });

    test('неизвестный вид строки отбрасывается, а не роняет разбор', () {
      final condition = EntryCondition.fromJson({
        'kinds': ['directory', 'wormhole'],
      });
      expect(condition.matches(entryOf(kind: EntryKind.directory)), isTrue);
      expect(condition.matches(entryOf()), isFalse);
    });

    test('чужой тип значения не считается заданным условием', () {
      // `hidden: "yes"` — не флаг; спрашивать про скрытое не будем вовсе.
      expect(EntryCondition.fromJson({'hidden': 'yes'}).matches(entryOf()), isTrue);
    });
  });
}
