import 'dart:async';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';
import 'panel_session.dart';

/// Ядро приложения со стороны линка.
///
/// Всё, что оно делает, — разбирает просьбы и рассылает события. Работу
/// работают сеансы панелей ([PanelSession]); сервер не знает ни как читается
/// каталог, ни что такое аренда. Так и задумано: сервер — это **дверь**, а не
/// ещё один слой логики (`docs/spec/client-server.md`, §6).
///
/// Экрана у этой стороны нет и быть не может: ни окна, ни команды, ни виджета
/// здесь не встретится — их типов эта сторона попросту не видит.
class CoreServer implements CoreHandler {
  CoreServer({required PanelSession left, required PanelSession right})
    : _panels = {PanelId.left: left, PanelId.right: right} {
    for (final entry in _panels.entries) {
      final panel = entry.key;
      final session = entry.value;
      session.onChanged = () => _say(PanelChanged(panel, session.state));
      session.onListed = () {
        // Список и состояние уезжают вместе: в состоянии лежит номер списка, и
        // приехать оно должно **после** самого списка — иначе та сторона
        // увидит номер, которому ещё нечего соответствовать.
        _say(PanelListed(panel, PanelListing(generation: session.generation, entries: session.entries)));
        _say(PanelChanged(panel, session.state));
      };
      session.onSized = (sizes) => _say(PanelSized(panel, session.generation, sizes));
    }
  }

  final Map<PanelId, PanelSession> _panels;

  /// Синхронно — и это важное свойство, а не мелочь настройки.
  ///
  /// События уходят в линк **в тот момент, когда случились**, то есть внутри
  /// исполнения просьбы, а ответ добавляется после её конца. Канал один и
  /// порядок в нём сохраняется, значит к приходу ответа та сторона уже знает
  /// всё, что ядро о себе рассказало: дождавшись «открылось», зеркало найдёт у
  /// себя и новый список. Через порт это верно ровно так же — сообщения
  /// приходят в порядке отправки.
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast(sync: true);

  @override
  Stream<CoreEvent> get events => _events.stream;

  PanelSession session(PanelId panel) => _panels[panel]!;

  void _say(CoreEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  @override
  Future<CoreReply?> handle(CoreRequest request) async {
    switch (request) {
      case Handshake():
        return CoreReady(
          states: {for (final entry in _panels.entries) entry.key: entry.value.state},
          listings: {
            for (final entry in _panels.entries)
              entry.key: PanelListing(generation: entry.value.generation, entries: entry.value.entries),
          },
        );

      case OpenPath(:final panel, :final path, :final allowConnect):
        final opened = await session(panel).openPath(path, allowConnect: allowConnect);
        return CoreOpened(opened);

      case OpenEntry(:final panel, :final entry):
        return _enter(session(panel), entry);

      case GoUp(:final panel):
        await session(panel).goUp();
        return const CoreDone();

      case Reload(:final panel):
        await session(panel).reload();
        return const CoreDone();

      case MoveCursor(:final panel, :final index, :final seq):
        session(panel).setCursorIndex(index, seq: seq);
        return null;

      case SetMarks(:final panel, :final names):
        session(panel).setMarks(names);
        return null;

      case ToggleMark(:final panel):
        session(panel).toggleCurrentMark();
        return null;

      case Arrange(:final panel, :final sort, :final columns, :final showHidden):
        final target = session(panel);
        if (columns != null) {
          target.setColumnLayout(columns);
        }
        if (sort != null) {
          target.sortTo(sort);
        }
        if (showHidden != null) {
          await target.setShowHidden(showHidden);
        }
        return const CoreDone();

      case MeasureDirectories(:final panel):
        session(panel).measureDirectories();
        return null;

      case CancelWork(:final panel):
        session(panel).cancel();
        return null;
    }
  }

  /// Войти в объект, названный ссылкой.
  ///
  /// Строка панели — обычный случай: пришли за тем, что видят на экране.
  /// Номер списка при этом сверяется, а не берётся на веру: пока сообщение
  /// шло, каталог могли перечитать, и строка под тем же местом — уже другая.
  Future<CoreReply> _enter(PanelSession session, EntryRef entry) async {
    switch (entry) {
      case PanelEntryRef(:final index, :final generation):
        if (generation != session.generation || index < 0 || index >= session.nodes.length) {
          // Список сменился — заявка ни о чём. Не беда: та сторона просто
          // увидит новый список и повторит, если человек нажмёт ещё раз.
          return const CoreEntered(null);
        }
        session.setCursorIndex(index);
        final blocked = await session.enterCurrent();
        return CoreEntered(blocked == null ? null : session.entryOf(blocked));

      case PathEntryRef(:final path):
        final opened = await session.openPath(path);
        if (opened) {
          return const CoreEntered(null);
        }
        final error = session.error;
        return error == null ? const CoreEntered(null) : CoreFailed(error);
    }
  }

  Future<void> dispose() async {
    for (final session in _panels.values) {
      session.dispose();
    }
    await _events.close();
  }
}
