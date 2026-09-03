import 'dart:isolate';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/link/isolate_link.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Порт как вторая дверь: тот же разговор, но через изолят.
///
/// Ядро здесь подставное — настоящее требует диска, дерева и настроек, и
/// проверялось бы уже не про линк. Проверяется ровно то, чем порт отличается от
/// петли: доставка, порядок и **смерть той стороны**
/// (`docs/spec/client-server.md`, §10).
void main() {
  test('просьба уходит и ответ возвращается', () async {
    final link = await IsolateLink.spawn(_answering, (back) => back);
    addTearDown(link.dispose);

    expect(await link.call(const GoUp(PanelId.left)), isA<CoreDone>());
  });

  test('порядок сохраняется: сказанное не обгоняет спрошенное', () async {
    final link = await IsolateLink.spawn(_counting, (back) => back);
    addTearDown(link.dispose);

    link.tell(const GoUp(PanelId.left));
    link.tell(const GoUp(PanelId.left));
    final reply = await link.call(const GoUp(PanelId.left)) as CoreEntries;

    // Третьим — значит, два первых доехали раньше.
    expect(reply.entries, hasLength(3));
  });

  test('события приезжают сами', () async {
    final link = await IsolateLink.spawn(_talking, (back) => back);
    addTearDown(link.dispose);

    final heard = <CoreEvent>[];
    link.events.listen(heard.add);
    await link.call(const GoUp(PanelId.left));

    expect(heard, isNotEmpty, reason: 'ядро рассказывает о себе само');
  });

  test('ядро упало — ждущий получает беду, а не тишину', () async {
    final link = await IsolateLink.spawn(_dying, (back) => back);
    addTearDown(link.dispose);

    // Молчаливый пустой ответ оставил бы работу ждать вечно
    // (`spec/client-server.md`, §11, урок 2).
    await expectLater(link.call(const GoUp(PanelId.left)), throwsA(isA<CoreCrashed>()));
  });

  test('ядра больше нет — и новые разговоры не начинаются', () async {
    final link = await IsolateLink.spawn(_dying, (back) => back);
    addTearDown(link.dispose);

    await expectLater(link.call(const GoUp(PanelId.left)), throwsA(isA<CoreCrashed>()));

    // Второй разговор кончается там же, где начался: обещать ответ некому.
    await expectLater(link.call(const GoUp(PanelId.left)), throwsA(isA<Object>()));
  });

  test('чужая беда переносится текстом', () async {
    final link = await IsolateLink.spawn(_failing, (back) => back);
    addTearDown(link.dispose);

    await expectLater(
      link.call(const GoUp(PanelId.left)),
      throwsA(isA<CoreCrashed>().having((it) => it.message, 'текст', contains('так вышло'))),
    );
  });
}

/// Отвечает на всё «сделано».
void _answering(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen((message) {
    if (message is LinkRequest && message.id != 0) {
      back.send(LinkReply(message.id, const CoreDone()));
    }
  });
}

/// Считает всё, что пришло, и отвечает счётом.
void _counting(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  var seen = 0;
  port.listen((message) {
    if (message is! LinkRequest) {
      return;
    }
    seen++;
    if (message.id != 0) {
      back.send(
        LinkReply(
          message.id,
          CoreEntries(List.filled(seen, const FileEntry(name: 'x', kind: EntryKind.file, path: ''))),
        ),
      );
    }
  });
}

/// Рассказывает о себе до того, как ответить.
void _talking(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen((message) {
    if (message is! LinkRequest) {
      return;
    }
    back.send(const LinkEvent(OperationEnded('run#1', OperationOutcome.done)));
    if (message.id != 0) {
      back.send(LinkReply(message.id, const CoreDone()));
    }
  });
}

/// Умирает, не ответив: так выглядит упавшее ядро.
void _dying(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen((message) {
    port.close();
    Isolate.current.kill(priority: Isolate.immediate);
  });
}

/// Отвечает бедой: исключение по ту сторону.
void _failing(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen((message) {
    if (message is LinkRequest) {
      back.send(LinkCrashed(message.id, 'так вышло', 'stack'));
    }
  });
}
