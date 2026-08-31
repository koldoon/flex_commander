import 'fake_pty.dart';

/// Подставная оболочка, которая держит уговор о метках.
///
/// Приложение просит оболочку отмечаться — перед запуском команды и перед
/// приглашением (`docs/spec/single-shell-session.md`, §3). Настоящая оболочка
/// делает это сама; подставной велит тест, и делает он это **по тому же
/// проводу**: число сессии берётся из строки уговора, которую приложение ей
/// прислало, а не выдаётся тесту отдельно. Разойдись формат метки с разбором —
/// тесты об этом узнают.
class AgreeingShell {
  AgreeingShell(this.pty, {this.directory = '/home'});

  final FakePtySession pty;

  /// Где стоит оболочка. Меняется вместе с тем, что она сообщает в метке.
  String directory;

  /// Число этой сессии — из строки уговора; null — уговора не присылали.
  String? get nonce => RegExp(r'777;fc;([0-9a-f]+);').firstMatch(pty.written)?.group(1);

  /// Первое приглашение: с него оболочка готова принимать команды.
  void greet({int code = 0}) => _prompt(code);

  /// Отражение команды, её вывод и снова приглашение — как у настоящей.
  ///
  /// [output] пусто — команда промолчала: экрана быть не должно.
  void finish({int code = 0, String output = '', String? directory}) {
    this.directory = directory ?? this.directory;
    // Уже отметилась о запуске — второй раз нельзя: настоящая оболочка так не
    // делает, а приложение по этой метке считает команду новой.
    if (!_started) {
      start();
    }
    if (output.isNotEmpty) {
      pty.emit(output);
    }
    _started = false;
    _prompt(code);
  }

  /// Команда пошла и ещё работает.
  void start() {
    _started = true;
    final id = nonce;
    if (id != null) {
      pty.emit('\x1b]777;fc;$id;r\x07');
    }
  }

  bool _started = false;

  void _prompt(int code) {
    final id = nonce;
    if (id != null) {
      pty.emit('\x1b]777;fc;$id;p;$code;$directory\x07');
    }
  }
}
