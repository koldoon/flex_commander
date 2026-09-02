import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// Повышение, которое запоминает, о чём его просили, и делает вид, что смогло.
class _FakeElevation implements Elevation {
  _FakeElevation({this.enabled = true, this.succeeds = true});

  @override
  final bool enabled;

  /// Вышло ли: `false` — человек отказался.
  final bool succeeds;

  final List<ElevationRequest> asked = [];

  /// Содержимое временного файла, каким оно было в миг переноса.
  String? carried;

  @override
  Future<bool> copyOver({
    required ShellHost host,
    required String temporary,
    required String target,
    required ElevationRequest about,
  }) async {
    asked.add(about);
    // Копировать по-настоящему нечем: прав у подставки столько же, сколько у
    // теста. Довольно того, что байты дошли до неё целыми — дальше дело
    // `sudo`, и проверяется оно в тестах самой службы.
    carried = await File(temporary).readAsString();
    return succeeds;
  }

  @override
  ElevationRequest? get pending => null;

  @override
  void answer(bool agreed) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Отказ по правам подхватывается провайдером и уходит в повышение.
void main() {
  late Directory temp;
  late Directory locked;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_elevated');
    locked = Directory('${temp.path}/locked')..createSync();
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+w', temp.path]);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Снять права на запись с каталога; false — не вышло (под `root`).
  Future<bool> lock() async {
    await Process.run('chmod', ['a-w', locked.path]);
    return !await File('${locked.path}/probe').exists() &&
        await Process.run('test', ['-w', locked.path]).then((r) => r.exitCode != 0);
  }

  Future<StreamSink<List<int>>> openWrite(LocalTreeProvider provider, String name) async {
    final root = await provider.resolvePath().run(locked.path);
    return provider.openWrite(root! as DirectoryNode, name);
  }

  test('в доступный каталог пишет как раньше, повышения не трогая', () async {
    final elevation = _FakeElevation();
    final provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false, elevation: () => elevation);

    final root = await provider.resolvePath().run(temp.path);
    final sink = await provider.openWrite(root! as DirectoryNode, 'plain.txt');
    sink.add(utf8.encode('обычная запись'));
    await sink.close();

    expect(File('${temp.path}/plain.txt').readAsStringSync(), 'обычная запись');
    expect(elevation.asked, isEmpty, reason: 'прав хватило — спрашивать не о чем');
  });

  test('нет прав — байты уходят через повышение, а не пропадают', () async {
    if (!await lock()) {
      return;
    }
    final elevation = _FakeElevation();
    final provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false, elevation: () => elevation);

    final sink = await openWrite(provider, 'squid.conf');
    sink.add(utf8.encode('правленое'));
    await sink.close();

    expect(elevation.asked, hasLength(1));
    expect(elevation.asked.single.path, endsWith('squid.conf'));
    expect(elevation.asked.single.where, 'localhost', reason: 'место названо даже на своей машине');
    expect(elevation.carried, 'правленое', reason: 'до `cp` дошло ровно написанное');
  });

  test('отказались от повышения — это отказ по правам, а не тишина', () async {
    if (!await lock()) {
      return;
    }
    final elevation = _FakeElevation(succeeds: false);
    final provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false, elevation: () => elevation);

    final sink = await openWrite(provider, 'squid.conf');
    sink.add(utf8.encode('мимо'));

    await expectLater(sink.close(), throwsA(isA<FsError>()));
  });

  test('временный файл за собой не остаётся', () async {
    if (!await lock()) {
      return;
    }
    final elevation = _FakeElevation();
    final provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false, elevation: () => elevation);

    final before = Directory.systemTemp.listSync().whereType<File>().where((f) => f.path.contains('fc-elevated'));
    expect(before, isEmpty, reason: 'начинаем с чистого');

    final sink = await openWrite(provider, 'squid.conf');
    sink.add(utf8.encode('раз'));
    await sink.close();

    final after = Directory.systemTemp.listSync().whereType<File>().where((f) => f.path.contains('fc-elevated'));
    expect(after, isEmpty, reason: 'он лежит в общем каталоге и содержит только что написанное');
  });

  test('выключенное повышение оставляет всё как было', () async {
    if (!await lock()) {
      return;
    }
    final elevation = _FakeElevation(enabled: false);
    final provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false, elevation: () => elevation);

    final sink = await openWrite(provider, 'squid.conf');
    sink.add(utf8.encode('мимо'));

    // Обычный отказ файловой системы — тот же, что был до всей затеи.
    await expectLater(sink.close(), throwsA(isA<Object>()));
    expect(elevation.asked, isEmpty);
  });
}
