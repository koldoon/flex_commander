import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Псевдотерминал средствами самой системы — без нативной части.
///
/// Здесь голый POSIX: `posix_openpt`, `posix_spawn`, `read`, `ioctl`. Всё это
/// лежит в libSystem (macOS) и libc (Linux), то есть доступно через
/// [DynamicLibrary.process] — своей библиотеки собирать не нужно, а значит и
/// CocoaPods в сборке macOS не нужен.
///
/// **Почему не `forkpty`.** Он делает `fork()`, и в потомке управление
/// возвращается в Dart — в среду, где от многопоточной виртуальной машины
/// остался один поток, а её замки остались захваченными мёртвыми потоками. Между `fork` и `exec` нельзя даже
/// выделить память, а Dart на возврате из вызова делает куда больше. `posix_spawn`
/// не разветвляет процесс в пространстве пользователя вовсе: ядро само создаёт
/// потомка и запускает в нём программу.
///
/// Управляющий терминал потомок получает так же, без `fork`: `POSIX_SPAWN_SETSID`
/// делает его главой сессии, а первое открытие терминала главой сессии без
/// управляющего терминала (`addopen` на дескриптор 0) этот терминал ему и
/// назначает — правило BSD, действующее и на macOS. Без этого `vim` и `htop`
/// работали бы, а `/dev/tty`, управление заданиями и `Ctrl-C` — нет.
class PosixPty {
  PosixPty._(this.master, this.pid, this.slavePath);

  /// Дескриптор ведущей стороны: сюда пишем и отсюда читаем.
  final int master;

  /// Идентификатор запущенного процесса.
  final int pid;

  /// Путь ведомой стороны (`/dev/ttys004`) — для отладки и тестов.
  final String slavePath;

  static bool get supported => Platform.isMacOS || Platform.isLinux;

  /// Открывает псевдотерминал и запускает в нём программу.
  ///
  /// Бросает [PtyError], если что-то из этого не вышло: подробность важна —
  /// «нет такой программы» и «кончились псевдотерминалы» лечатся по-разному.
  static PosixPty start({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    String? workingDirectory,
    int columns = 80,
    int rows = 24,
  }) {
    if (!supported) {
      throw PtyError('A pseudo-terminal is not supported on ${Platform.operatingSystem}');
    }

    final libc = _Libc.instance;
    final master = libc.posixOpenpt(_oRdwr | _oNoctty);
    if (master < 0) {
      throw PtyError('Could not open a pseudo-terminal (posix_openpt)');
    }

    if (libc.grantpt(master) != 0 || libc.unlockpt(master) != 0) {
      libc.close(master);
      throw PtyError('Could not unlock the terminal slave side (grantpt/unlockpt)');
    }

    final slaveName = libc.ptsname(master);
    if (slaveName == nullptr) {
      libc.close(master);
      throw PtyError('Could not get the slave side name (ptsname)');
    }
    final slavePath = slaveName.toDartString();

    // Ведомая сторона открывается **и здесь тоже**, до запуска, ради одного:
    // размера окна. Пока её не открыл никто, терминала ещё нет, и `TIOCSWINSZ`
    // на ведущей стороне пропадает впустую — программа видит нули и верстает
    // по ним. Проверено `stty size`: без этого он отвечает «0 0».
    //
    // Держать её открытой нельзя: пока ведомая сторона открыта хоть кем-то,
    // чтение не увидит конца, и работа программы не кончится никогда. Поэтому
    // закрывается сразу после запуска — свою копию потомок к тому времени уже
    // получил.
    final slave = libc.open(slaveName.cast(), _oRdwr | _oNoctty);
    if (slave >= 0) {
      _resize(libc, slave, columns: columns, rows: rows);
    }

    final arena = Arena();
    try {
      final actions = arena<Pointer<Void>>();
      final attributes = arena<Pointer<Void>>();
      _check(libc.fileActionsInit(actions), 'posix_spawn_file_actions_init');
      _check(libc.attrInit(attributes), 'posix_spawnattr_init');

      // Открывает ведомую сторону **в потомке** — уже после `setsid`. Этим он
      // и получает управляющий терминал.
      _check(libc.fileActionsAddOpen(actions, 0, slaveName.cast(), _oRdwr, 0), 'posix_spawn_file_actions_addopen');
      _check(libc.fileActionsAddDup2(actions, 0, 1), 'posix_spawn_file_actions_adddup2');
      _check(libc.fileActionsAddDup2(actions, 0, 2), 'posix_spawn_file_actions_adddup2');
      // Ведущая сторона потомку не нужна вовсе, и оставлять её ему нельзя:
      // пока она открыта хоть кем-то, чтение не увидит конца.
      _check(libc.fileActionsAddClose(actions, master), 'posix_spawn_file_actions_addclose');
      _check(libc.attrSetFlags(attributes, _posixSpawnSetsid), 'posix_spawnattr_setflags');

      if (workingDirectory != null) {
        // Каталога в файловых действиях нет на Linux со старой glibc, поэтому
        // проверяем сами: иначе программа тихо запустилась бы не там.
        if (!Directory(workingDirectory).existsSync()) {
          throw PtyError('Directory $workingDirectory does not exist');
        }
        _check(libc.fileActionsAddChdir(actions, workingDirectory.toNativeUtf8(allocator: arena)), 'addchdir');
      }

      final argv = _toArray(arena, [executable, ...arguments]);
      final envp = _toArray(arena, [
        for (final entry in _environmentFor(environment).entries) '${entry.key}=${entry.value}',
      ]);
      final pid = arena<Int32>();

      final code = libc.spawnp(pid, executable.toNativeUtf8(allocator: arena).cast(), actions, attributes, argv, envp);
      libc.fileActionsDestroy(actions);
      libc.attrDestroy(attributes);
      if (slave >= 0) {
        libc.close(slave);
      }

      if (code != 0) {
        libc.close(master);
        // Код возврата — это errno: «нет такой программы» (2) человек должен
        // увидеть словами, а не числом.
        throw PtyError('Could not start $executable: ${_errorText(code)}');
      }

      return PosixPty._(master, pid.value, slavePath);
    } finally {
      arena.releaseAll();
    }
  }

  /// Сообщает программе новый размер окна.
  void resize({required int columns, required int rows}) =>
      _resize(_Libc.instance, master, columns: columns, rows: rows);

  /// Пишет программе на вход. Возвращает, сколько байт ушло.
  int write(List<int> data) {
    if (data.isEmpty) {
      return 0;
    }
    final libc = _Libc.instance;
    final buffer = calloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      var sent = 0;
      while (sent < data.length) {
        final written = libc.write(master, buffer + sent, data.length - sent);
        if (written <= 0) {
          break;
        }
        sent += written;
      }
      return sent;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Просит программу закончить.
  void terminate() => _Libc.instance.kill(pid, _sigterm);

  /// Закрывает ведущую сторону. Программа увидит это как конец ввода.
  void closeMaster() => _Libc.instance.close(master);

  static void _resize(_Libc libc, int fd, {required int columns, required int rows}) {
    final size = calloc<_WinSize>();
    try {
      size.ref
        ..rows = rows
        ..columns = columns
        ..pixelWidth = 0
        ..pixelHeight = 0;
      libc.ioctl(fd, _tiocswinsz, size.cast());
    } finally {
      calloc.free(size);
    }
  }

  /// Окружение потомка: наше плюс то, без чего псевдотерминал бесполезен.
  ///
  /// **Наследуется, а не заменяется.** Пустое окружение стоило кириллицы: без
  /// `LANG` оболочка считает UTF-8 побайтно, и `Backspace` стирает половину
  /// двухбайтового символа — на экране остаётся мусор. Без `PATH` не находится
  /// ничего, без `HOME` не читаются настройки.
  ///
  /// `TERM` ставится всегда: программа по нему решает, что она умеет, а
  /// незаданный означает «дурной терминал» — без цветов, без перерисовки и без
  /// строчного редактора у оболочки.
  static Map<String, String> _environmentFor(Map<String, String> extra) {
    final environment = <String, String>{...Platform.environment};
    environment['TERM'] = 'xterm-256color';
    // Локаль — только если её нет: чужую менять нельзя, человек мог выбрать
    // свою нарочно.
    if (!environment.containsKey('LANG') && !environment.containsKey('LC_ALL')) {
      environment['LANG'] = 'en_US.UTF-8';
    }
    environment.addAll(extra);
    return environment;
  }

  static Pointer<Pointer<Utf8>> _toArray(Arena arena, List<String> values) {
    final array = arena<Pointer<Utf8>>(values.length + 1);
    for (var i = 0; i < values.length; i++) {
      array[i] = values[i].toNativeUtf8(allocator: arena);
    }
    array[values.length] = nullptr;
    return array;
  }

  static void _check(int code, String call) {
    if (code != 0) {
      throw PtyError('$call: ${_errorText(code)}');
    }
  }

  static String _errorText(int code) => switch (code) {
    2 => 'program not found',
    13 => 'not allowed to run',
    _ => 'error $code',
  };
}

/// Что пошло не так с псевдотерминалом.
class PtyError implements Exception {
  const PtyError(this.message);

  final String message;

  @override
  String toString() => message;
}

// --- константы платформы ---

const int _oRdwr = 0x2;
final int _oNoctty = Platform.isMacOS ? 0x20000 : 0x100;
final int _tiocswinsz = Platform.isMacOS ? 0x80087467 : 0x5414;
final int _posixSpawnSetsid = Platform.isMacOS ? 0x0400 : 0x80;
const int _sigterm = 15;

/// Что и с каким исходом ждать: `struct pollfd`.
final class _PollFd extends Struct {
  @Int32()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

/// «Есть что читать» — одинаково на macOS и Linux.
const int _pollIn = 0x0001;

/// `EINTR`: вызов прервали сигналом, это не ошибка.
const int _eintr = 4;

final class _WinSize extends Struct {
  @Uint16()
  external int rows;

  @Uint16()
  external int columns;

  @Uint16()
  external int pixelWidth;

  @Uint16()
  external int pixelHeight;
}

/// Символы libc/libSystem, которыми всё это делается.
///
/// Отдельным классом, а не набором верхнеуровневых переменных: связывать их
/// приходится и в изоляте чтения, а он живёт своей жизнью и общей памяти с
/// нами не имеет.
class _Libc {
  _Libc._(this._library);

  factory _Libc.bind() => _Libc._(DynamicLibrary.process());

  static final _Libc instance = _Libc.bind();

  final DynamicLibrary _library;

  late final posixOpenpt = _library.lookupFunction<Int32 Function(Int32), int Function(int)>('posix_openpt');
  late final grantpt = _library.lookupFunction<Int32 Function(Int32), int Function(int)>('grantpt');
  late final unlockpt = _library.lookupFunction<Int32 Function(Int32), int Function(int)>('unlockpt');
  late final ptsname = _library.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('ptsname');

  late final close = _library.lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  /// `open` объявлен с переменным числом аргументов, но третий (права) читается
  /// только при `O_CREAT` — мы его не передаём, и обычного объявления хватает:
  /// обязательные аргументы едут в регистрах при любом соглашении.
  late final open = _library.lookupFunction<Int32 Function(Pointer<Int8>, Int32), int Function(Pointer<Int8>, int)>(
    'open',
  );
  late final kill = _library.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('kill');

  late final read = _library
      .lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr), int Function(int, Pointer<Uint8>, int)>('read');
  late final write = _library
      .lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr), int Function(int, Pointer<Uint8>, int)>('write');

  /// Ожидание готовности с ограничением по времени — вместо вечного `read`.
  late final poll = _library
      .lookupFunction<Int32 Function(Pointer<_PollFd>, UnsignedLong, Int32), int Function(Pointer<_PollFd>, int, int)>(
        'poll',
      );

  /// `errno` живёт в потоке, и добираются до него по-разному.
  late final errno = _library.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
    Platform.isMacOS ? '__error' : '__errno_location',
  );

  late final waitpid = _library
      .lookupFunction<Int32 Function(Int32, Pointer<Int32>, Int32), int Function(int, Pointer<Int32>, int)>('waitpid');

  /// `ioctl` — функция с переменным числом аргументов, и это не мелочь: на
  /// Apple Silicon такие аргументы едут по стеку, а не в регистрах. Объяви мы
  /// её обычной трёхаргументной — размер окна уехал бы в никуда.
  late final ioctl = _library.lookupFunction<
    Int32 Function(Int32, UnsignedLong, VarArgs<(Pointer<Void>,)>),
    int Function(int, int, Pointer<Void>)
  >('ioctl');

  late final fileActionsInit = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>(
        'posix_spawn_file_actions_init',
      );
  late final fileActionsDestroy = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>(
        'posix_spawn_file_actions_destroy',
      );
  late final fileActionsAddOpen = _library.lookupFunction<
    Int32 Function(Pointer<Pointer<Void>>, Int32, Pointer<Int8>, Int32, Uint16),
    int Function(Pointer<Pointer<Void>>, int, Pointer<Int8>, int, int)
  >('posix_spawn_file_actions_addopen');
  late final fileActionsAddDup2 = _library.lookupFunction<
    Int32 Function(Pointer<Pointer<Void>>, Int32, Int32),
    int Function(Pointer<Pointer<Void>>, int, int)
  >('posix_spawn_file_actions_adddup2');
  late final fileActionsAddClose = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>, Int32), int Function(Pointer<Pointer<Void>>, int)>(
        'posix_spawn_file_actions_addclose',
      );

  /// `_np` — non-portable: имя одно и то же и на macOS, и в glibc, но
  /// стандартом не закреплено.
  late final fileActionsAddChdir = _library.lookupFunction<
    Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>),
    int Function(Pointer<Pointer<Void>>, Pointer<Utf8>)
  >('posix_spawn_file_actions_addchdir_np');

  late final attrInit = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>(
        'posix_spawnattr_init',
      );
  late final attrDestroy = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>(
        'posix_spawnattr_destroy',
      );
  late final attrSetFlags = _library
      .lookupFunction<Int32 Function(Pointer<Pointer<Void>>, Int16), int Function(Pointer<Pointer<Void>>, int)>(
        'posix_spawnattr_setflags',
      );

  late final spawnp = _library.lookupFunction<
    Int32 Function(
      Pointer<Int32>,
      Pointer<Int8>,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
    ),
    int Function(
      Pointer<Int32>,
      Pointer<Int8>,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
    )
  >('posix_spawnp');
}

/// Чтение вывода и ожидание конца — то, что делается в отдельном изоляте.
///
/// Вынесено сюда, чтобы у изолята не было ничего лишнего: он получает число
/// (дескриптор) и порт, а всё остальное связывает у себя.
class PtyReader {
  static const int bufferSize = 64 * 1024;

  /// Сколько ждать готовности за раз.
  ///
  /// Не «сколько можно»: изолят, висящий в системном вызове, до точки останова
  /// не доходит — его нельзя ни остановить, ни разобрать вместе с группой. На
  /// этом спотыкается перезапуск приложения (hot restart): корневой изолят
  /// пересоздаётся **внутри того же процесса**, и застрявший сосед этому мешает.
  /// Поэтому ожидание ограничено: раз в четверть секунды управление возвращается
  /// в Dart, и остановить изолят становится можно.
  static const int waitMs = 250;

  /// Читает, пока читается, и отдаёт прочитанное в [port].
  ///
  /// Конец ведомой стороны приходит как `EIO` (или ноль байт): для
  /// псевдотерминала это обычное «все закрыли», а не ошибка.
  static void run((int, int, SendPort) request) {
    final (fd, pid, port) = request;
    final libc = _Libc.bind();
    final buffer = calloc<Uint8>(bufferSize);
    final waiting = calloc<_PollFd>();
    try {
      waiting.ref
        ..fd = fd
        ..events = _pollIn
        ..revents = 0;

      while (true) {
        final ready = libc.poll(waiting, 1, waitMs);
        if (ready < 0) {
          if (libc.errno().value == _eintr) {
            continue;
          }
          break;
        }
        if (ready == 0) {
          // Программа молчит. Это не повод висеть в системном вызове: сходили
          // в Dart — и обратно.
          continue;
        }

        final count = libc.read(fd, buffer, bufferSize);
        if (count <= 0) {
          break;
        }
        port.send(Uint8List.fromList(buffer.asTypedList(count)));
      }
    } finally {
      calloc.free(buffer);
      calloc.free(waiting);
    }

    port.send(_exitCodeOf(libc, pid));
  }

  /// Ждёт конца программы и разбирает её состояние.
  ///
  /// Убитый сигналом отдаёт отрицательное число — так же, как `dart:io`:
  /// прерванная `Ctrl-C` команда не должна выглядеть успешной.
  static int _exitCodeOf(_Libc libc, int pid) {
    final status = calloc<Int32>();
    try {
      final result = libc.waitpid(pid, status, 0);
      if (result < 0) {
        return -1;
      }
      final value = status.value;
      final signal = value & 0x7f;
      return signal == 0 ? (value >> 8) & 0xff : -signal;
    } finally {
      calloc.free(status);
    }
  }
}
