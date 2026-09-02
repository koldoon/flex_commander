import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подставное ядро: помнит, о чём его просили, и отвечает как велено.
class _Core implements CoreHandler {
  final List<CoreRequest> seen = [];
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast();

  /// Чем отвечать; по умолчанию — «сделано».
  Future<CoreReply?> Function(CoreRequest request)? answer;

  @override
  Stream<CoreEvent> get events => _events.stream;

  @override
  Future<CoreReply?> handle(CoreRequest request) async {
    seen.add(request);
    final reply = answer;
    if (reply != null) {
      return reply(request);
    }
    return const CoreDone();
  }

  void say(CoreEvent event) => _events.add(event);

  Future<void> close() => _events.close();
}

void main() {
  late _Core core;
  late Link link;

  setUp(() {
    core = _Core();
    link = LoopbackLink(core);
  });

  tearDown(() async {
    await link.dispose();
    await core.close();
  });

  test('ответ возвращается тому, кто спрашивал', () async {
    core.answer = (request) async => CoreOpened(request is OpenPath && request.path == '/home');

    final yes = await link.call(const OpenPath(PanelId.left, '/home'));
    final no = await link.call(const OpenPath(PanelId.left, '/etc'));

    expect((yes as CoreOpened).opened, isTrue);
    expect((no as CoreOpened).opened, isFalse);
  });

  test('ответы связываются с просьбами по имени, а не по порядку', () async {
    // Первая просьба отвечает медленнее второй: ответ обязан прийти той, что
    // спрашивала, а не той, что дождалась первой.
    core.answer = (request) async {
      final path = (request as OpenPath).path;
      if (path == '/slow') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return CoreOpened(path == '/slow');
    };

    final slow = link.call(const OpenPath(PanelId.left, '/slow'));
    final fast = link.call(const OpenPath(PanelId.left, '/fast'));

    expect((await fast as CoreOpened).opened, isFalse);
    expect((await slow as CoreOpened).opened, isTrue);
  });

  test('сказанное без ответа не обгоняет спрошенное', () async {
    // Очередь одна: «поставь курсор» уйдёт после «открой каталог», даже если
    // ответа у него нет вовсе и уходит он не дожидаясь.
    final opening = link.call(const OpenPath(PanelId.left, '/home'));
    link.tell(const MoveCursor(PanelId.left, 3, 1));
    await opening;
    await pumpEventQueue();

    expect(core.seen.map((request) => request.runtimeType), [OpenPath, MoveCursor]);
  });

  test('беда на той стороне приезжает бедой, а не молчанием', () async {
    core.answer = (request) async => throw StateError('всё сломалось');

    await expectLater(
      link.call(const GoUp(PanelId.left)),
      throwsA(isA<CoreCrashed>().having((crash) => crash.message, 'текст', contains('всё сломалось'))),
    );
  });

  test('беда переносится текстом и стеком: тип по дороге пропадает', () async {
    core.answer = (request) async => throw const FsError('/home', FsErrorKind.notFound);

    try {
      await link.call(const GoUp(PanelId.left));
      fail('ожидалась беда');
    } on CoreCrashed catch (crash) {
      expect(crash.message, contains('/home'));
      expect(crash.trace, isNotEmpty, reason: 'без стека причину искать вдвое дороже');
    }
  });

  test('события ядра доходят до слушателя', () async {
    final heard = <CoreEvent>[];
    final subscription = link.events.listen(heard.add);

    core.say(
      PanelChanged(PanelId.right, PanelState(source: const SourceInfo(scheme: 'fs'), columns: ColumnLayout([]))),
    );
    await pumpEventQueue();
    await subscription.cancel();

    expect(heard, hasLength(1));
    expect((heard.single as PanelChanged).panel, PanelId.right);
  });

  test('закрытый линк кончает ожидающих бедой, а не тишиной', () async {
    core.answer = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return const CoreDone();
    };

    final pending = link.call(const GoUp(PanelId.left));
    // Ожидание ставится до закрытия: беда приходит прямо из `dispose`, и
    // подписаться на неё позже — значит поймать её уже неперехваченной.
    final expectation = expectLater(pending, throwsA(isA<CoreCrashed>()));

    await link.dispose();
    await expectation;
  });

  test('мёртвому линку говорят в тишину, а спрашивают с ошибкой', () async {
    await link.dispose();

    link.tell(const MoveCursor(PanelId.left, 1, 1));
    await expectLater(link.call(const GoUp(PanelId.left)), throwsA(isA<StateError>()));
  });
}
