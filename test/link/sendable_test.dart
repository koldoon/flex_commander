import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отправляемость **всех** сообщений — эхо-изолятом и заранее.
///
/// Урок ветки `isolated-core`, за который уже заплачено: сообщение, которое не
/// поедет через порт, обнаруживается не на разъезде, а на живом приложении —
/// и выглядит как «нажал и ничего не произошло». Проверять это надо до того,
/// как порт появится (`docs/spec/client-server.md`, §11, урок 1).
///
/// Проверка **списочная**: сюда добавляется каждое новое сообщение протокола.
/// Забыть про новое — значит узнать о нём живьём.
void main() {
  late SendPort echo;
  late ReceivePort back;
  late Isolate isolate;
  late StreamQueue<Object?> answers;

  setUp(() async {
    back = ReceivePort();
    final ready = Completer<SendPort>();
    final incoming = back.asBroadcastStream();
    final first = incoming.first;
    isolate = await Isolate.spawn(_echo, back.sendPort);
    ready.complete(await first as SendPort);
    echo = await ready.future;
    answers = StreamQueue<Object?>(incoming);
  });

  tearDown(() async {
    await answers.cancel();
    back.close();
    isolate.kill(priority: Isolate.immediate);
  });

  /// Отправляет сообщение эхо-изоляту и возвращает то, что приехало обратно.
  Future<Object?> roundtrip(Object? message) async {
    echo.send(message);
    return answers.next;
  }

  /// Каждое сообщение — своей проверкой: падение называет виновника само.
  void sendable(String what, LinkMessage message) {
    test(what, () async {
      final back = await roundtrip(message);
      expect(back, isA<LinkMessage>(), reason: 'сообщение должно пережить порт');
    });
  }

  const entry = FileEntry(
    name: 'notes.txt',
    kind: EntryKind.file,
    path: '/home/notes.txt',
    directoryPath: '/home',
    size: 3,
    scheme: 'fs',
    realPath: '/home/notes.txt',
  );
  const listing = PanelListing(generation: 1, entries: [entry]);
  final state = PanelState(source: const SourceInfo(scheme: 'fs'), columns: ColumnLayout.defaults);
  const ref = EntryRef.inPanel(PanelId.left, 0, 1);

  group('просьбы', () {
    sendable('рукопожатие', const LinkRequest(1, Handshake()));
    sendable('запуск ядра', const LinkRequest(1, StartCore()));
    sendable('открыть путь', const LinkRequest(1, OpenPath(PanelId.left, '/home')));
    sendable('войти в строку', const LinkRequest(1, OpenEntry(PanelId.left, ref)));
    sendable('уровень вверх', const LinkRequest(1, GoUp(PanelId.left)));
    sendable('перечитать', const LinkRequest(1, Reload(PanelId.left)));
    sendable('курсор', const LinkRequest(0, MoveCursor(PanelId.left, 3, 7)));
    sendable('пометка', LinkRequest(0, SetMarks(PanelId.left, const {'a', 'b'})));
    sendable('переключить пометку', const LinkRequest(0, ToggleMark(PanelId.left)));
    sendable('вид', const LinkRequest(1, Arrange(PanelId.left, showHidden: true)));
    sendable('строка состояния', const LinkRequest(0, SetStatusText(PanelId.left, 'Loading…')));
    sendable('заголовок', const LinkRequest(0, SetHeaderText(PanelId.left, 'Found')));
    sendable('подсчёт размеров', const LinkRequest(0, MeasureDirectories(PanelId.left)));
    sendable('прервать', const LinkRequest(0, CancelWork(PanelId.left)));
    sendable('закрыть панель', const LinkRequest(0, ClosePanel(PanelId.left)));
    sendable(
      'завести работу',
      LinkRequest(1, RunOperation('run#1', OperationSpec(kind: 'file.copy', targets: Targets.marked(PanelId.left)))),
    );
    sendable('отмена работы', const LinkRequest(0, TellOperation('run#1', CancelInput())));
    sendable('ответ работе', const LinkRequest(0, TellOperation('run#1', AnswerInput('overwrite'))));
    sendable('ввод в оболочку', const LinkRequest(0, TellOperation('shell@localhost', ShellInput([104, 105]))));
    sendable('размер окна', const LinkRequest(0, TellOperation('shell@localhost', ShellResize(columns: 80, rows: 24))));
    sendable('читать содержимое', const LinkRequest(0, ReadContent('read#1', ref)));
    sendable('права на запись', const LinkRequest(1, CheckWriteAccess(ref)));
    sendable('оболочка', const LinkRequest(1, OpenShell(panel: PanelId.left)));
    sendable('имена в каталоге', const LinkRequest(1, ListNames(PanelId.left, '/home')));
    sendable('показать находки', const LinkRequest(1, ShowFound(PanelId.left, 'run#1', title: '*.dart')));
    sendable('секрет', LinkRequest(0, AnswerCredential('secret#1', Credential.password('тайна'), realm: '7z:/a.7z')));
    sendable('повышение', const LinkRequest(0, AnswerElevation('sudo#1', agreed: true)));
    sendable('настройки', const LinkRequest(0, ChangeSettings(UiSettings(splitRatio: 0.3))));
    sendable('записать настройки', const LinkRequest(1, SaveSettings()));
    sendable('выход', const LinkRequest(1, Shutdown()));
  });

  group('ответы', () {
    sendable('сделано', const LinkReply(1, CoreDone()));
    sendable('беда', const LinkReply(1, CoreFailed(FsError('/home', FsErrorKind.notFound))));
    sendable('открылось', const LinkReply(1, CoreOpened(true)));
    sendable('вошли', const LinkReply(1, CoreEntered(entry)));
    sendable('флаг', const LinkReply(1, CoreFlag(true)));
    sendable('строки', const LinkReply(1, CoreEntries([entry])));
    sendable('оболочка открыта', const LinkReply(1, ShellOpened('shell@localhost', label: 'localhost', fresh: true)));
    sendable(
      'рукопожатие',
      LinkReply(
        1,
        CoreReady(
          states: {PanelId.left: state, PanelId.right: state},
          listings: const {PanelId.left: listing, PanelId.right: listing},
        ),
      ),
    );
  });

  group('события', () {
    sendable('панель', LinkEvent(PanelChanged(PanelId.left, state)));
    sendable('список', const LinkEvent(PanelListed(PanelId.left, listing)));
    sendable('размеры', const LinkEvent(PanelSized(PanelId.left, 1, {0: 42})));
    sendable('кусок байт', const LinkEvent(ContentChunk('read#1', [1, 2, 3])));
    sendable('конец байтов', const LinkEvent(ContentEnded('read#1')));
    sendable('вывод оболочки', const LinkEvent(ShellOutput('shell@localhost', [104, 105])));
    sendable('конец оболочки', const LinkEvent(ShellExited('shell@localhost', 0)));
    sendable('находки', const LinkEvent(OperationFound('run#1', [entry])));
    sendable('ход работы', const LinkEvent(OperationProgress('run#1', ProgressReport(message: 'Copying…'))));
    sendable(
      'вопрос работы',
      const LinkEvent(
        OperationAsked(
          'run#1',
          AskSpec(message: 'Overwrite?', options: {'overwrite': 'Yes'}, enterOptionId: 'overwrite'),
        ),
      ),
    );
    sendable('вопрос снят', const LinkEvent(OperationAskCanceled('run#1')));
    sendable('работа кончилась', const LinkEvent(OperationEnded('run#1', OperationOutcome.done)));
    sendable(
      'секрет',
      const LinkEvent(
        CredentialAsked('secret#1', CredentialRequest(realm: '7z:/a.7z', title: 'Archive', message: 'a.7z')),
      ),
    );
    sendable(
      'повышение',
      const LinkEvent(
        ElevationAsked('sudo#1', ElevationRequest(action: 'Write', path: '/etc/hosts', where: 'localhost')),
      ),
    );
    sendable('беда', const LinkCrashed(1, 'ядро упало', 'stack'));
  });
}

/// Эхо: что приехало, то и уехало обратно.
///
/// Само по себе ничего не проверяет — проверяет **порт**: непроходимое
/// сообщение он не пропустит, и `send` бросит там, где его позвали.
void _echo(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen(back.send);
}
