import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import '../link/link.dart';
import 'content_hub.dart';
import 'operation_hub.dart';
import 'panel_session.dart';
import 'settings_hub.dart';
import 'search_results.dart';
import 'shell_hub.dart';

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
  CoreServer({
    required PanelSession left,
    required PanelSession right,
    ProviderRegistry? registry,
    TreeEditor editor = const TreeTransferEngine(),
    FcServices services = const _NoServices(),
    Map<String, OperationFactory> operations = const {},
    SettingsHub? settings,
  }) : _panels = {PanelId.left: left, PanelId.right: right},
       _settings = settings {
    _content = ContentHub(registry: registry, sessionOf: session, say: _say);
    _shells = ShellHub(services: services, sessionOf: session, say: _say);
    _operations = OperationHub(
      factories: operations,
      services: services,
      editor: editor,
      registry: registry,
      sessionOf: session,
      say: _say,
    );
    for (final entry in _panels.entries) {
      final panel = entry.key;
      final session = entry.value;
      session.watch(
        onChanged: () {
          // Настройки панели — её же состояние: каталог, курсор, колонки,
          // сортировка. Спрашивать их у экрана было бы кругом.
          _settings?.panelsChanged();
          _say(PanelChanged(panel, session.state));
        },
        onListed: () {
          // Список и состояние уезжают вместе: в состоянии лежит номер списка,
          // и приехать оно должно **после** самого списка — иначе та сторона
          // увидит номер, которому ещё нечего соответствовать.
          _say(PanelListed(panel, PanelListing(generation: session.generation, entries: session.entries)));
          _say(PanelChanged(panel, session.state));
        },
        onSized: (sizes) => _say(PanelSized(panel, session.generation, sizes)),
      );
    }
  }

  final Map<PanelId, PanelSession> _panels;

  /// Настройки приложения; null — ядро собрано без них (проверка границы).
  final SettingsHub? _settings;

  /// Заведённые работы: копирование, упаковка, подсчёт.
  late final OperationHub _operations;

  /// Идущие чтения: просмотр, правка, сведения об объекте.
  late final ContentHub _content;

  /// Оболочки мест: своя машина и каждый сервер, куда зашла панель.
  late final ShellHub _shells;

  /// Кто слушает события ядра.
  ///
  /// Прямыми вызовами, а не потоком: событие уходит слушателю **в тот момент,
  /// когда случилось**, то есть внутри исполнения просьбы, а ответ добавляется
  /// после её конца. Значит, к приходу ответа та сторона уже знает всё, что
  /// ядро о себе рассказало: дождавшись «открылось», зеркало найдёт у себя и
  /// новый список. Через порт это верно ровно так же — сообщения приходят в
  /// порядке отправки.
  final List<void Function(CoreEvent event)> _listeners = [];

  @override
  VoidCallback listen(void Function(CoreEvent event) onEvent) {
    _listeners.add(onEvent);
    return () => _listeners.remove(onEvent);
  }

  PanelSession session(PanelId panel) => _panels[panel]!;

  /// Настройки такими, какими они уйдут в файл; null — ядро собрано без них.
  ///
  /// Наружу — ради проверок и справки: спрашивают их у того, кто ими и владеет.
  AppSettings? get settings => _settings?.settings;

  void _say(CoreEvent event) {
    for (final listener in _listeners.toList()) {
      listener(event);
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
          ui: _settings?.ui ?? const UiSettings(),
        );

      case StartCore():
        await start();
        return const CoreDone();

      case ChangeSettings(:final ui):
        _settings?.applyUi(ui);
        return null;

      case SaveSettings():
        await _settings?.save();
        return const CoreDone();

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

      case SetStatusText(:final panel, :final text):
        session(panel).setStatusText(text);
        return null;

      case SetHeaderText(:final panel, :final text):
        session(panel).setHeaderText(text);
        return null;

      case MeasureDirectories(:final panel):
        session(panel).measureDirectories();
        return null;

      case ClosePanel(:final panel):
        session(panel).close();
        return null;

      case CancelWork(:final panel):
        session(panel).cancel();
        return null;

      case RunOperation(:final runId, :final spec):
        // Не ждём: работа живёт своей жизнью, а о ходе дела рассказывает
        // событиями. Ждать её здесь значило бы держать очередь просьб.
        unawaited(_operations.run(runId, spec));
        return const CoreDone();

      case TellOperation(:final runId, :final input):
        // Оболочке — первой: имя разговора у неё своё, и работой она не
        // притворяется.
        if (_shells.tell(runId, input)) {
          return null;
        }
        _operations.tell(runId, input);
        // Отмена относится и к чтению: имя разговора одно, а кто им занят —
        // работа или чтение, — той стороне знать незачем.
        if (input is CancelInput) {
          _content.stop(runId);
        }
        return null;

      case CheckWriteAccess(:final entry):
        return CoreFlag(await _content.canWrite(entry));

      case ShowFound(:final panel, :final runId, :final title):
        final found = _operations.takeFound(runId);
        if (found.isEmpty) {
          return const CoreOpened(false);
        }
        // Каталог поиска — родитель списка: `..` из находок возвращает туда,
        // где панель стояла, и никакого «запомненного места» для этого не
        // нужно.
        final results = SearchResults(title: title, found: found, parent: session(panel).directory);
        await session(panel).open(results.rootDirectory);
        return const CoreOpened(true);

      case ListNames(:final panel, :final path):
        return CoreEntries(await session(panel).namesIn(path));

      case OpenShell():
        return _shells.open(request);

      case ReadContent(:final runId, :final entry, :final offset):
        // Не ждём: байты поедут событиями, а очередь просьб держать нельзя.
        unawaited(_content.read(runId, entry, offset: offset));
        return const CoreDone();
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

  /// Открыть панели там, где их оставили.
  ///
  /// Первым делом и до всякого экрана: интерфейс подписывается на готовое, а
  /// не смотрит, как оно собирается. Обе разом — вторая не должна ждать первую.
  Future<void> start() async {
    await Future.wait([for (final entry in _panels.entries) _restore(entry.value)]);
    // Открытие панелей — не изменение настроек: там ровно то, что в файле и
    // лежало, и записывать это заново незачем.
    _settings?.remember();
  }

  /// Панель встаёт туда, где её оставили; не вышло — домой, не вышло — в
  /// корень.
  ///
  /// Без подключения: восстановление состояния не должно ходить в сеть.
  /// Сохранённый адрес сервера означал бы вопрос о пароле поверх ещё пустых
  /// панелей, а недоступный сервер — ожидание до истечения времени подключения
  /// при каждом запуске. На сервер человек возвращается сам — так же ведут
  /// себя Total Commander и Far.
  Future<void> _restore(PanelSession session) async {
    final path = session.savedPath;
    if (path.isNotEmpty && await session.openPath(path, allowConnect: false)) {
      return;
    }
    if (await session.openPath(session.provider.homePath)) {
      return;
    }
    await session.openPath(session.provider.rootDirectory.pathString);
  }

  Future<void> dispose() async {
    _settings?.dispose();
    _content.dispose();
    _operations.dispose();
    _shells.dispose();
    for (final session in _panels.values) {
      session.dispose();
    }
    _listeners.clear();
  }
}

/// Служб нет вовсе: так собирают ядро в проверках, где работ не объявлено.
class _NoServices implements FcServices {
  const _NoServices();

  @override
  T resolve<T>() => throw StateError('Ядро собрано без служб');

  @override
  List<T> resolveAll<T>() => const [];
}
