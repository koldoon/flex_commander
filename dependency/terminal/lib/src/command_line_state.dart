import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import 'terminal_settings.dart';

/// Командная строка под панелями.
///
/// Стоит в [ViewportPosition.bottom] всё время работы приложения и никуда
/// оттуда не уходит: полоса — это место, а не наложение. Ввод она получает по
/// просьбе (`Cmd-T`) и отдаёт обратно по `Esc`.
///
/// Каталог, историю и приглашение держит она; кто и как их показывает — дело
/// вида, а кто и когда выполняет — дело команд.
class CommandLineState extends ChangeNotifier implements ViewportState {
  CommandLineState({required this.app, required this.settings, required this.save});

  final Application app;
  final TerminalSettings settings;

  /// Отложенная запись настроек — та же, что у панелей.
  final void Function() save;

  final TextEditingController text = TextEditingController();

  /// Куда ввод возвращается по `Esc` и чей каталог показан в приглашении.
  ///
  /// Панель-**источник**, а не активная область: активна в этот момент как раз
  /// строка.
  Panel? get panel => app.view.panelAt(app.view.sourceArea);

  /// Каталог, в котором выполнится команда; null — выполнять нельзя.
  ///
  /// Настоящий путь или ничего: молча выполнить команду не в том каталоге, о
  /// котором думает человек, — худшее, что строка может сделать. В архиве и на
  /// `ssh://` она приглушена и говорит, почему.
  String? get workingDirectory {
    final directory = panel?.directory;
    if (directory == null) {
      return null;
    }
    return directory.provider.capabilities.realFileSystem ? directory.pathString : null;
  }

  /// Что показано слева от ввода: путь, в котором всё и произойдёт.
  String get prompt => panel?.directory?.pathString ?? '';

  /// Строку можно выполнить здесь.
  bool get enabled => workingDirectory != null;

  bool get isEmpty => text.text.trim().isEmpty;

  @override
  bool get takesKeyboard => true;

  // --- история ---

  /// Где мы в истории; длина списка означает «в набранном».
  int _cursor = 0;

  /// Набранное до захода в историю: возвращается, когда дошли обратно вниз.
  String _draft = '';

  List<String> get history => settings.history;

  /// Запомнить выполненное.
  ///
  /// Подряд повторённая команда не удваивается: пролистывать десять одинаковых
  /// `make` — не история, а помеха.
  void remember(String line) {
    if (line.isEmpty) {
      return;
    }
    if (history.isEmpty || history.last != line) {
      history.add(line);
      if (history.length > TerminalSettings.historyLimit) {
        history.removeRange(0, history.length - TerminalSettings.historyLimit);
      }
      save();
    }
    _cursor = history.length;
    _draft = '';
  }

  /// Шаг назад по истории.
  void previous() {
    if (history.isEmpty || _cursor == 0) {
      return;
    }
    if (_cursor == history.length) {
      _draft = text.text;
    }
    _show(history[--_cursor]);
  }

  /// Шаг вперёд; с последней команды возвращает набранное.
  void next() {
    if (_cursor >= history.length) {
      return;
    }
    _cursor++;
    _show(_cursor == history.length ? _draft : history[_cursor]);
  }

  void clear() {
    text.clear();
    _cursor = history.length;
    _draft = '';
    notifyListeners();
  }

  /// Вставить в место курсора — имя файла, путь, что угодно.
  void insert(String value) {
    final selection = text.selection;
    final base = text.text;
    // Выделения может не быть вовсе: поле ни разу не трогали, и `TextField`
    // держит `TextSelection.collapsed(offset: -1)`.
    final at = selection.isValid ? selection.start : base.length;
    final end = selection.isValid ? selection.end : base.length;
    final needsSpace = at > 0 && !base.substring(0, at).endsWith(' ');
    final inserted = needsSpace ? ' $value' : value;

    text.value = TextEditingValue(
      text: base.replaceRange(at, end, inserted),
      selection: TextSelection.collapsed(offset: at + inserted.length),
    );
    notifyListeners();
  }

  void _show(String line) {
    text.value = TextEditingValue(text: line, selection: TextSelection.collapsed(offset: line.length));
    notifyListeners();
  }

  @override
  void close() => text.dispose();
}
