import 'dart:async';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вложенные источники: реестр фабрик по схеме и монтирование над узлом.
///
/// Провайдер архива ничего не знает о том, над чем он смонтирован, а локальная
/// ФС — о существовании архивов. Связывает их только реестр: это композиция,
/// а не наследование.
void main() {
  late InMemoryTreeProvider disk;
  late ProviderRegistry registry;
  late List<FsNode> mountedOver;

  List<FakeEntry> archiveEntries() => [
    FakeEntry.directory('/inner'),
    FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
    FakeEntry.file('/readme.md', content: [4]),
    // Архив внутри архива: показанный путь и через него должен разбираться.
    FakeEntry.file('/nested.arc', content: [0]),
  ];

  setUp(() {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ]);
    mountedOver = [];

    registry = ProviderRegistry(root: disk)..register(
      'arc',
      (host) => TaskOperation<TreeProvider>((op) async {
        mountedOver.add(host);
        return InMemoryArchiveProvider(archiveEntries(), host);
      }),
      extensions: {'arc'},
    );
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath(path).result)!;

  group('чем открывать', () {
    test('расширение выбирает схему', () async {
      expect(registry.schemeFor(await nodeAt('/home/archive.arc')), 'arc');
    });

    test('незнакомое расширение не открывается ничем', () async {
      // Такой объект панель отдаст системе, а не станет читать как дерево.
      expect(registry.schemeFor(await nodeAt('/home/notes.txt')), isNull);
    });

    test('каталог не открывается как архив: в него и так входят', () async {
      expect(registry.schemeFor(await nodeAt('/home')), isNull);
    });

    test('незарегистрированная схема — отказ, а не пустое дерево', () async {
      final host = await nodeAt('/home/archive.arc');

      await expectLater(registry.mount('zip', host).result, throwsA(isA<FsError>()));
    });
  });

  group('монтирование', () {
    test('корень смонтированного провайдера стоит над узлом-хозяином', () async {
      final host = await nodeAt('/home/archive.arc');

      final mounted = await registry.mount('arc', host).result;

      expect(mountedOver.single, same(host));
      expect(mounted.rootDirectory.parent, same(host));
      // Наверх из архива — в каталог, где он лежит, а не в никуда.
      expect(mounted.rootDirectory.parentDirectory?.name, 'home');
    });

    test('путь внутри провайдера чужих имён не содержит', () async {
      final mounted = await registry.mount('arc', await nodeAt('/home/archive.arc')).result;
      final inner = (await mounted.resolvePath('/inner/doc.txt').result)!;

      // Провайдер архива знает только свою часть пути.
      expect(mounted.pathOf(inner), '/inner/doc.txt');
    });

    test('полный путь собирается через оба дерева', () async {
      final mounted = await registry.mount('arc', await nodeAt('/home/archive.arc')).result;
      final inner = (await mounted.resolvePath('/inner/doc.txt').result)!;

      // Ровно тот формат, который умеет разбирать NodePath.
      expect(inner.pathString, '/home/archive.arc:arc:/inner/doc.txt');
    });
  });

  group('разбор цепочки', () {
    test('путь проходит через оба провайдера', () async {
      final node = await registry.resolvePath('/home/archive.arc:arc:/inner/doc.txt').result;

      expect(node?.name, 'doc.txt');
      expect(node?.provider, isA<InMemoryArchiveProvider>());
      expect(node?.pathString, '/home/archive.arc:arc:/inner/doc.txt');
    });

    test('обычный путь — это цепочка из одной части', () async {
      final node = await registry.resolvePath('/home/notes.txt').result;

      expect(node?.name, 'notes.txt');
      expect(node?.provider, same(disk));
    });

    test('несуществующего внутри архива нет', () async {
      expect(await registry.resolvePath('/home/archive.arc:arc:/missing').result, isNull);
    });

    test('нет хозяина — нечего и монтировать', () async {
      expect(await registry.resolvePath('/home/missing.arc:arc:/inner').result, isNull);
    });

    test('чужая схема в начале пути — отказ', () async {
      // Второй корневой провайдер появится вместе с сетевым (5.6).
      await expectLater(registry.resolvePath('sftp:/host/dir').result, throwsA(isA<FsError>()));
    });
  });

  group('разбор показанного пути', () {
    test('архив в пути опознаётся по типу узла, а не по схеме', () async {
      final node = await registry.resolveDisplayPath('/home/archive.arc/inner/doc.txt').result;

      expect(node?.name, 'doc.txt');
      expect(node?.provider, isA<InMemoryArchiveProvider>());
      // Наружу узел выходит с полным машинным путём: он и уйдёт в настройки.
      expect(node?.pathString, '/home/archive.arc:arc:/inner/doc.txt');
      expect(node?.displayPath, '/home/archive.arc/inner/doc.txt');
    });

    test('путь без архива разбирается одним обращением', () async {
      final node = await registry.resolveDisplayPath('/home/notes.txt').result;

      expect(node?.name, 'notes.txt');
      expect(node?.provider, same(disk));
      // Быстрый путь: монтировать было нечего.
      expect(mountedOver, isEmpty);
    });

    test('архив в архиве — тем же способом', () async {
      final node = await registry.resolveDisplayPath('/home/archive.arc/nested.arc/inner/doc.txt').result;

      expect(node?.name, 'doc.txt');
      expect(node?.pathString, '/home/archive.arc:arc:/nested.arc:arc:/inner/doc.txt');
      expect(mountedOver, hasLength(2));
    });

    test('сам архив остаётся файлом: входит в него панель, а не разбор', () async {
      final node = await registry.resolveDisplayPath('/home/archive.arc').result;

      expect(node, isA<FileNode>());
      expect(node, isNot(isA<DirectoryNode>()));
      expect(mountedOver, isEmpty);
    });

    test('машинный путь со схемами разбирается по-прежнему', () async {
      final node = await registry.resolveDisplayPath('/home/archive.arc:arc:/inner/doc.txt').result;

      expect(node?.pathString, '/home/archive.arc:arc:/inner/doc.txt');
    });

    test('несуществующего внутри архива нет — и это не исключение', () async {
      expect(await registry.resolveDisplayPath('/home/archive.arc/missing').result, isNull);
    });

    test('обычный файл посреди пути архивом не притворяется', () async {
      // `notes.txt` открывать нечем: значит пути правда нет.
      expect(await registry.resolveDisplayPath('/home/notes.txt/inner').result, isNull);
      expect(mountedOver, isEmpty);
    });

    test('не разобралось — смонтированное по дороге закрыто', () async {
      final opened = <InMemoryArchiveProvider>[];
      final registry = ProviderRegistry(root: disk)..register(
        'arc',
        (host) => TaskOperation<TreeProvider>((op) async {
          final provider = InMemoryArchiveProvider(archiveEntries(), host);
          opened.add(provider);
          return provider;
        }),
        extensions: {'arc'},
      );

      expect(await registry.resolveDisplayPath('/home/archive.arc/missing').result, isNull);

      // Архив держит открытый файл, и бросить его молча нельзя.
      expect(opened.single.closed, isTrue);
    });

    test('битый архив — отказ открыть, а не «пути нет»', () async {
      final registry = ProviderRegistry(root: disk)..register(
        'arc',
        (host) => TaskOperation<TreeProvider>((op) async => throw FsError(host.pathString, FsErrorKind.io)),
        extensions: {'arc'},
      );

      await expectLater(
        registry.resolveDisplayPath('/home/archive.arc/inner').result,
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.io)),
      );
    });

    test('уже смонтированный берётся, а не заводится второй', () async {
      final mounted = await registry.mount('arc', await nodeAt('/home/archive.arc')).result;
      expect(mountedOver, hasLength(1));

      final node = await registry.resolveDisplayPath('/home/archive.arc/readme.md', reuse: [mounted]).result;

      expect(node?.name, 'readme.md');
      // Второй экземпляр поверх того же файла разошёлся бы с первым состоянием.
      expect(node?.provider, same(mounted));
      expect(mountedOver, hasLength(1));
    });
  });

  group('аренда смонтированного', () {
    test('второй арендатор получает тот же экземпляр', () async {
      final host = await nodeAt('/home/archive.arc');

      final first = await registry.acquire('arc', host).result;
      final second = await registry.acquire('arc', host).result;

      // Два экземпляра поверх одного файла разошлись бы состоянием: записанное
      // через один не увидел бы другой.
      expect(second.provider, same(first.provider));
      expect(mountedOver, hasLength(1));
      expect(registry.mounted.single.tenants, 2);
    });

    test('закрывает последний ушедший', () async {
      final host = await nodeAt('/home/archive.arc');
      final first = await registry.acquire('arc', host).result;
      final second = await registry.acquire('arc', host).result;
      final provider = first.provider as InMemoryArchiveProvider;

      await first.release();
      expect(provider.closed, isFalse, reason: 'второй арендатор ещё читает');

      await second.release();
      expect(provider.closed, isTrue);
      expect(registry.mounted, isEmpty);
    });

    test('второе освобождение той же аренды ничего не делает', () async {
      final host = await nodeAt('/home/archive.arc');
      final lease = await registry.acquire('arc', host).result;
      final other = await registry.acquire('arc', host).result;

      // Отпускать полагается из `finally`, куда попадают дважды.
      await lease.release();
      await lease.release();

      expect((other.provider as InMemoryArchiveProvider).closed, isFalse);
      expect(registry.mounted.single.tenants, 1);
    });

    test('leaseOf делает арендатором того, у кого провайдер уже на руках', () async {
      final host = await nodeAt('/home/archive.arc');
      final lease = await registry.acquire('arc', host).result;

      final second = registry.leaseOf(lease.provider)!;
      await lease.release();

      expect((second.provider as InMemoryArchiveProvider).closed, isFalse);
      await second.release();
      expect((second.provider as InMemoryArchiveProvider).closed, isTrue);
    });

    test('общий корень не арендуется', () async {
      // Его никто не монтировал, в таблице его нет, и отпускать нечего.
      expect(registry.leaseOf(disk), isNull);
    });

    test('аренда внутреннего держит внешний', () async {
      final outer = await registry.acquire('arc', await nodeAt('/home/archive.arc')).result;
      final nested = (await outer.provider.resolvePath('/nested.arc').result)!;
      final inner = await registry.acquire('arc', nested).result;

      // Внешний нужен внутреннему: его файл — это данные внутреннего.
      await outer.release();
      expect((outer.provider as InMemoryArchiveProvider).closed, isFalse);
      expect(registry.mounted, hasLength(2));

      await inner.release();
      expect((inner.provider as InMemoryArchiveProvider).closed, isTrue);
      expect((outer.provider as InMemoryArchiveProvider).closed, isTrue, reason: 'внутренний ушёл — внешний свободен');
      expect(registry.mounted, isEmpty);
    });

    test('одинаковый путь у разных источников — разные архивы', () async {
      final other = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/archive.arc', content: [0]),
      ]);
      final host = await nodeAt('/home/archive.arc');
      final twin = (await other.resolvePath('/home/archive.arc').result)!;

      final first = await registry.acquire('arc', host).result;
      final second = await registry.acquire('arc', twin).result;

      // Строка одна, а файлы разные: один на диске, другой на сервере.
      expect(second.provider, isNot(same(first.provider)));
      expect(registry.mounted, hasLength(2));
    });

    test('неудачное монтирование записи не оставляет', () async {
      final broken = ProviderRegistry(root: disk)..register(
        'arc',
        (host) => CompletedOperation<TreeProvider>.error(const FsError('/home/archive.arc', FsErrorKind.io)),
        extensions: {'arc'},
      );

      await expectLater(broken.acquire('arc', await nodeAt('/home/archive.arc')).result, throwsA(isA<FsError>()));

      expect(broken.mounted, isEmpty);
    });

    test('незарегистрированная схема — отказ, а не запись в таблице', () async {
      await expectLater(registry.acquire('zip', await nodeAt('/home/archive.arc')).result, throwsA(isA<FsError>()));

      expect(registry.mounted, isEmpty);
    });

    group('пока открывается', () {
      late Completer<void> door;
      late List<InMemoryArchiveProvider> opened;
      late ProviderRegistry slow;

      setUp(() {
        door = Completer<void>();
        opened = [];
        slow = ProviderRegistry(root: disk)..register(
          'arc',
          (host) => TaskOperation<TreeProvider>((op) {
            op.message('Unpacking ${host.name}');
            return ProviderRegistry.keepUnlessCanceled(op, () async {
              await door.future;
              final provider = InMemoryArchiveProvider(archiveEntries(), host);
              opened.add(provider);
              return provider;
            }());
          }),
          extensions: {'arc'},
        );
      });

      tearDown(() {
        if (!door.isCompleted) {
          door.complete();
        }
      });

      test('второй арендатор ждёт то же монтирование, а не заводит второе', () async {
        final host = await nodeAt('/home/archive.arc');
        final first = slow.acquire('arc', host);
        final second = slow.acquire('arc', host);
        await pumpEventQueue();

        expect(slow.mounted.single.opening, isTrue);
        expect(slow.mounted.single.tenants, 2);

        door.complete();
        expect((await first.result).provider, same((await second.result).provider));
        expect(opened, hasLength(1));
      });

      test('ушедший арендатор работы остальных не прерывает', () async {
        final host = await nodeAt('/home/archive.arc');
        final first = slow.acquire('arc', host);
        final second = slow.acquire('arc', host);
        await pumpEventQueue();

        first.cancel();
        await expectLater(first.result, throwsA(isA<OperationCanceled>()));
        door.complete();

        // Ждали двое, ушёл один: архив всё равно нужен второму.
        expect((await second.result).provider, isNotNull);
        expect(opened.single.closed, isFalse);
      });

      test('ушли все — монтирование прерывается', () async {
        final host = await nodeAt('/home/archive.arc');
        final only = slow.acquire('arc', host);
        await pumpEventQueue();

        only.cancel();
        await expectLater(only.result, throwsA(isA<OperationCanceled>()));
        door.complete();
        await pumpEventQueue();

        // Ждать некому: опоздавший провайдер закрывает сама фабрика.
        expect(slow.mounted, isEmpty);
        expect(opened.single.closed, isTrue);
      });

      test('веха монтирования доходит до каждого арендатора', () async {
        final host = await nodeAt('/home/archive.arc');
        final first = slow.acquire('arc', host);
        final second = slow.acquire('arc', host);
        final heard = <String>[];
        second.progress.listen((event) {
          if (event.message.isNotEmpty) {
            heard.add(event.message);
          }
        });

        door.complete();
        await first.result;
        await second.result;
        await pumpEventQueue();

        // Второй ждёт чужое монтирование — и всё равно знает, чего ждёт.
        expect(heard, contains('Unpacking archive.arc'));
      });

      test('acquire во время закрытия ждёт его и монтирует заново', () async {
        final host = await nodeAt('/home/archive.arc');
        door.complete();
        final lease = await slow.acquire('arc', host).result;
        final first = lease.provider as InMemoryArchiveProvider;

        // Отпускаем и тут же просим снова: между этими двумя вызовами нельзя
        // получить умирающий экземпляр — у 7z это ещё и перечитанное
        // оглавление, подменённое пересборкой.
        final releasing = lease.release();
        final second = await slow.acquire('arc', host).result;
        await releasing;

        expect(first.closed, isTrue);
        expect(second.provider, isNot(same(first)));
        expect((second.provider as InMemoryArchiveProvider).closed, isFalse);
      });
    });

    test('на выходе закрывается всё, не спрашивая счётчиков', () async {
      final host = await nodeAt('/home/archive.arc');
      final lease = await registry.acquire('arc', host).result;

      await registry.disposeAll();

      expect((lease.provider as InMemoryArchiveProvider).closed, isTrue);
      expect(registry.mounted, isEmpty);
    });
  });

  group('ход разбора', () {
    /// Собирает сообщения операции по порядку, без повторов подряд.
    Future<List<String>> messagesOf(AsyncOperation<Object?> operation) async {
      final seen = <String>[];
      operation.progress.listen((event) {
        if (event.message.isNotEmpty && (seen.isEmpty || seen.last != event.message)) {
          seen.add(event.message);
        }
      });
      await operation.result;
      await pumpEventQueue();
      return seen;
    }

    test('каждое звено цепочки называет себя', () async {
      final messages = await messagesOf(registry.resolvePath('/home/archive.arc:arc:/inner/doc.txt'));

      expect(messages, ['Reading archive.arc…']);
    });

    test('вложенные архивы называются по порядку вложенности', () async {
      // Показанный путь схем не содержит, и звенья в нём находит сам разбор —
      // тем важнее рассказать, на каком из них работа стоит.
      final messages = await messagesOf(registry.resolveDisplayPath('/home/archive.arc/nested.arc/readme.md'));

      expect(messages, ['Reading archive.arc…', 'Reading nested.arc…']);
    });

    test('прогресс провайдера доходит наверх', () async {
      final talking = ProviderRegistry(root: _TalkingProvider(disk));

      final messages = await messagesOf(talking.resolvePath('/home/notes.txt'));

      expect(messages, ['Looking up /home/notes.txt']);
    });

    test('прогресс фабрики доходит наверх', () async {
      final talking = ProviderRegistry(root: disk)..register(
        'arc',
        (host) => TaskOperation<TreeProvider>((op) async {
          op.message('Unpacking ${host.name}');
          return InMemoryArchiveProvider(archiveEntries(), host);
        }),
        extensions: {'arc'},
      );

      final messages = await messagesOf(talking.resolveDisplayPath('/home/archive.arc/readme.md'));

      // Веха реестра — про звено, веха фабрики — про то, чем она занята внутри.
      expect(messages, ['Reading archive.arc…', 'Unpacking archive.arc']);
    });

    test('отмена доходит до провайдера', () async {
      final slow = _SlowProvider(disk);
      final operation = ProviderRegistry(root: slow).resolvePath('/home/notes.txt');
      await pumpEventQueue();

      operation.cancel();

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      expect(slow.canceled, isTrue);
    });

    test('отменённая фабрика закрывает опоздавший провайдер', () async {
      // Самое долгое место открытия — окно пароля: пока его набирают, отменить
      // успевают не раз, а тело фабрики всё равно доработает до конца.
      final door = Completer<void>();
      final opened = <InMemoryArchiveProvider>[];
      final slow = ProviderRegistry(root: disk)..register(
        'arc',
        (host) => TaskOperation<TreeProvider>((op) {
          return ProviderRegistry.keepUnlessCanceled(op, () async {
            await door.future;
            final provider = InMemoryArchiveProvider(archiveEntries(), host);
            opened.add(provider);
            return provider;
          }());
        }),
        extensions: {'arc'},
      );

      final operation = slow.resolveDisplayPath('/home/archive.arc/readme.md');
      await pumpEventQueue();
      operation.cancel();
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));

      // Фабрика доделывает своё уже после отмены — и убирает за собой сама:
      // больше ссылки на открытый архив ни у кого нет.
      door.complete();
      await pumpEventQueue();
      expect(opened.single.closed, isTrue);
    });
  });
}

/// Провайдер, который рассказывает о разборе пути.
class _TalkingProvider extends _ForwardingProvider {
  _TalkingProvider(super.inner);

  @override
  AsyncOperation<FsNode?> resolvePath(String path) => TaskOperation<FsNode?>((op) async {
    op.message('Looking up $path');
    return inner.resolvePath(path).result;
  });
}

/// Провайдер, у которого разбор пути не кончается сам.
class _SlowProvider extends _ForwardingProvider {
  _SlowProvider(super.inner);

  bool canceled = false;

  @override
  AsyncOperation<FsNode?> resolvePath(String path) {
    final operation = TaskOperation<FsNode?>((op) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return null;
    });
    operation.result.catchError((Object _) {
      canceled = true;
      return null;
    });
    return operation;
  }
}

/// Провайдер, во всём повторяющий другой: наследникам остаётся подменить одно.
class _ForwardingProvider extends InMemoryTreeProvider {
  _ForwardingProvider(this.inner);

  final InMemoryTreeProvider inner;

  @override
  DirectoryNode get rootDirectory => inner.rootDirectory;

  @override
  String get homePath => inner.homePath;

  @override
  AsyncOperation<FsNode?> resolvePath(String path) => inner.resolvePath(path);

  @override
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = true}) =>
      inner.getDirectoryListing(dir, includeHidden: includeHidden);
}
