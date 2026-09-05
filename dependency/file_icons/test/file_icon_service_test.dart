import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Значки системы, за которыми видно, о чём и сколько раз спрашивали.
class FakeSystemIcons implements SystemIcons {
  final List<String> asked = [];
  bool answers = true;

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) async {
    asked.add('path:$path@$pixels');
    return answers ? Uint8List.fromList([1, 2, 3]) : null;
  }

  @override
  Future<Uint8List?> forExtension(String extension, {required int pixels}) async {
    asked.add('ext:$extension@$pixels');
    return answers ? Uint8List.fromList([4, 5, 6]) : null;
  }
}

/// Тип по содержимому, который отвечает по команде теста.
class FakeContentTypes implements ContentTypes {
  ContentType? answer;
  int detects = 0;
  final Completer<void> gate = Completer<void>();

  ContentType? _known;

  @override
  ContentType? known(FileEntry entry) => _known;

  @override
  Future<ContentType?> detect(FileEntry entry, Content Function() open, {bool Function()? stillWanted}) async {
    detects++;
    await gate.future;
    _known = answer;
    return _known;
  }
}

/// Картинки, о диске не знающие: тест сам говорит, какие есть.
class FakePictures implements PictureFiles {
  FakePictures(this.available);

  final Set<String> available;

  @override
  ImageProvider? of(String path) => available.contains(path) ? MemoryImage(Uint8List.fromList([7])) : null;

  @override
  String expand(String path) => path;
}

FileEntry file(String name, {String realPath = '', bool executable = false}) => FileEntry(
  name: name,
  kind: EntryKind.file,
  path: 'fs:/tmp/$name',
  realPath: realPath,
  size: 16,
  executable: executable,
);

FileEntry directory(String name, {String realPath = ''}) =>
    FileEntry(name: name, kind: EntryKind.directory, path: 'fs:/tmp/$name', realPath: realPath);

void main() {
  FileIconService serviceOf(
    FileIconSettings settings, {
    SystemIcons? system,
    ContentTypes? types,
    Set<String> pictures = const {},
  }) => FileIconService(
    settings: () => settings,
    systemIcons: system,
    contentTypes: types,
    pictures: FakePictures(pictures),
  );

  group('Встроенный хвост', () {
    final service = serviceOf(FileIconSettings());

    test('каталог — папка', () {
      expect(
        service.resolve(directory('src'), pixels: 13).now,
        isA<IconRole>().having((i) => i.role, 'role', 'folder'),
      );
    });

    test('обычный файл — ничего, но место остаётся', () {
      expect(service.resolve(file('notes.txt'), pixels: 13).now, isA<IconNothing>());
    });

    test('исполняемый — звёздочка', () {
      expect(
        service.resolve(file('run', executable: true), pixels: 13).now,
        isA<IconRole>().having((i) => i.role, 'role', 'asterisk'),
      );
    });

    test('битое узнаётся раньше каталога', () {
      final broken = FileEntry(name: 'gone', kind: EntryKind.directory, path: 'fs:/tmp/gone', broken: true);
      expect(service.resolve(broken, pixels: 13).now, isA<IconRole>().having((i) => i.role, 'role', 'exclamation'));
    });

    test('уточнять нечего', () {
      expect(service.resolve(file('notes.txt'), pixels: 13).later, isNull);
    });
  });

  group('Правила', () {
    test('первое совпавшее выигрывает, а не последнее', () {
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const GlyphRoleSource('check')),
          FileIconRule(when: EntryCondition(mask: '*'), icon: const GlyphRoleSource('link')),
        ],
      );
      final icon = serviceOf(settings).resolve(file('main.dart'), pixels: 13).now;
      expect(icon, isA<IconRole>().having((i) => i.role, 'role', 'check'));
    });

    test('глиф кодом', () {
      final settings = FileIconSettings(
        rules: [FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const GlyphCodeSource(0xf07b))],
      );
      expect(
        serviceOf(settings).resolve(file('main.dart'), pixels: 13).now,
        isA<IconGlyph>().having((i) => i.codePoint, 'codePoint', 0xf07b),
      );
    });

    test('картинка с диска', () {
      final settings = FileIconSettings(
        rules: [FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const PictureSource('~/dart.png'))],
      );
      final service = serviceOf(settings, pictures: {'~/dart.png'});
      expect(service.resolve(file('main.dart'), pixels: 13).now, isA<IconPicture>());
    });

    test('картинки нет — правило пропускается, и работает следующее', () {
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const PictureSource('~/missing.png')),
          FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const GlyphRoleSource('check')),
        ],
      );
      expect(
        serviceOf(settings).resolve(file('main.dart'), pixels: 13).now,
        isA<IconRole>().having((i) => i.role, 'role', 'check'),
      );
    });

    test('условие складывается по «и»', () {
      final settings = FileIconSettings(
        rules: [
          FileIconRule(
            when: EntryCondition(mask: '*.dart', kinds: {EntryKind.directory}),
            icon: const GlyphRoleSource('check'),
          ),
        ],
      );
      expect(serviceOf(settings).resolve(file('main.dart'), pixels: 13).now, isA<IconNothing>());
    });
  });

  group('Значок системы', () {
    test('обычный файл спрашивается по расширению, и только один раз', () async {
      final system = FakeSystemIcons();
      final settings = FileIconSettings(rules: [FileIconRule(when: EntryCondition(), icon: const SystemIconSource())]);
      final service = serviceOf(settings, system: system);

      final first = service.resolve(file('a.txt', realPath: '/tmp/a.txt'), pixels: 26);
      expect(first.now, isA<IconNothing>(), reason: 'пока значка нет, работает хвост');
      expect(await first.later, isA<IconPicture>());

      // Второй такой же файл: значок тот же, и вопрос не повторяется.
      final second = service.resolve(file('b.txt', realPath: '/tmp/b.txt'), pixels: 26);
      expect(second.now, isA<IconPicture>());
      expect(second.later, isNull);
      expect(system.asked, ['ext:txt@26']);
    });

    test('«..» спрашивается по пути того каталога, куда ведёт', () async {
      final system = FakeSystemIcons();
      final settings = FileIconSettings(system: true);
      final parent = FileEntry(name: '..', kind: EntryKind.parent, path: '', realPath: '/Users');

      await serviceOf(settings, system: system).resolve(parent, pixels: 26).later;
      expect(system.asked, ['path:/Users@26']);
    });

    test('пакет спрашивается по пути', () async {
      final system = FakeSystemIcons();
      final settings = FileIconSettings(rules: [FileIconRule(when: EntryCondition(), icon: const SystemIconSource())]);
      final service = serviceOf(settings, system: system);

      await service.resolve(directory('Safari.app', realPath: '/Applications/Safari.app'), pixels: 26).later;
      expect(system.asked, ['path:/Applications/Safari.app@26']);
    });

    test('без пути, что-то значащего для системы, правило не совпадает', () {
      final system = FakeSystemIcons();
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(), icon: const SystemIconSource()),
          FileIconRule(when: EntryCondition(), icon: const GlyphRoleSource('check')),
        ],
      );
      // Строка из архива: `realPath` пуст.
      final answer = serviceOf(settings, system: system).resolve(file('a.txt'), pixels: 26);
      expect(answer.now, isA<IconRole>().having((i) => i.role, 'role', 'check'));
      expect(answer.later, isNull);
      expect(system.asked, isEmpty);
    });

    test('система молчит — работает следующее правило', () async {
      final system = FakeSystemIcons()..answers = false;
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(), icon: const SystemIconSource()),
          FileIconRule(when: EntryCondition(), icon: const GlyphRoleSource('check')),
        ],
      );
      final service = serviceOf(settings, system: system);

      expect(await service.resolve(file('a.txt', realPath: '/tmp/a.txt'), pixels: 26).later, isA<IconRole>());
      // И второй раз не спрашиваем: молчание запомнено.
      expect(service.resolve(file('c.txt', realPath: '/tmp/c.txt'), pixels: 26).later, isNull);
      expect(system.asked.length, 1);
    });

    test('флаг ниже правил', () async {
      final system = FakeSystemIcons();
      final settings = FileIconSettings(
        system: true,
        rules: [FileIconRule(when: EntryCondition(mask: '*.dart'), icon: const GlyphRoleSource('check'))],
      );
      final service = serviceOf(settings, system: system);

      // Правило перекрывает флаг.
      final ruled = service.resolve(file('main.dart', realPath: '/tmp/main.dart'), pixels: 26);
      expect(ruled.now, isA<IconRole>());
      expect(system.asked, isEmpty);

      // Всё остальное достаётся флагу.
      expect(await service.resolve(file('a.txt', realPath: '/tmp/a.txt'), pixels: 26).later, isA<IconPicture>());
      expect(system.asked, ['ext:txt@26']);
    });

    test('без флага и без правил система не спрашивается вовсе', () {
      final system = FakeSystemIcons();
      final answer = serviceOf(
        FileIconSettings(),
        system: system,
      ).resolve(file('a.txt', realPath: '/a.txt'), pixels: 26);
      expect(answer.later, isNull);
      expect(system.asked, isEmpty);
    });
  });

  group('Правило по содержимому', () {
    test('сперва хвост, потом уточнение', () async {
      final types =
          FakeContentTypes()..answer = const ContentType('png', title: 'PNG image', group: ContentGroup.image);
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(contentGroup: {'image'}), icon: const GlyphRoleSource('check')),
        ],
      );
      final service = serviceOf(settings, types: types);

      final answer = service.resolve(file('photo.dat'), pixels: 13, open: () => throw StateError('не нужен'));
      expect(answer.now, isA<IconNothing>(), reason: 'тип неизвестен — правило не совпало');
      expect(answer.later, isNotNull);

      types.gate.complete();
      expect(await answer.later, isA<IconRole>().having((i) => i.role, 'role', 'check'));
      expect(types.detects, 1);
    });

    test('каталог о содержимом не спрашивают', () {
      final types = FakeContentTypes();
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(contentGroup: {'image'}), icon: const GlyphRoleSource('check')),
        ],
      );
      final answer = serviceOf(
        settings,
        types: types,
      ).resolve(directory('pictures'), pixels: 13, open: () => throw StateError('не нужен'));

      expect(answer.later, isNull);
      expect(types.detects, 0);
    });

    test('без службы типов правило по содержимому просто не совпадает', () {
      final settings = FileIconSettings(
        rules: [
          FileIconRule(when: EntryCondition(contentType: {'png'}), icon: const GlyphRoleSource('check')),
        ],
      );
      final answer = serviceOf(settings).resolve(file('photo.dat'), pixels: 13);
      expect(answer.now, isA<IconNothing>());
      expect(answer.later, isNull);
    });
  });

  test('размер — то, что в настройках', () {
    expect(serviceOf(FileIconSettings()).size, 0);
    expect(serviceOf(FileIconSettings(size: 24)).size, 24);
  });
}
