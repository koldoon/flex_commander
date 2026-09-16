import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'completion.dart';
import 'shell_prompt.dart';
import 'shell_session.dart';
import 'terminal_session.dart';
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
  CommandLineState({required this.app, required this.settings, required this.save, this.shells});

  final Application app;
  final TerminalSettings settings;

  /// Оболочки — ради приглашения: строка показывает то, что напечатала
  /// оболочка того места, где стоит панель (`docs/spec/shell-prompt.md`).
  ///
  /// Необязательно: без модуля оболочек строка живёт по-старому — путь и `$`.
  final ShellSession? shells;

  /// Отложенная запись настроек — та же, что у панелей.
  final void Function() save;

  final TextEditingController text = TextEditingController();

  /// Куда ввод возвращается по `Esc` и чей каталог показан в приглашении.
  ///
  /// Панель-**источник**, а не активная область: активна в этот момент как раз
  /// строка.
  Session? get panel => app.view.panelAt(app.view.sourceArea);

  /// Каталог, в котором выполнится команда; null — выполнять нельзя.
  ///
  /// Настоящий путь или ничего: молча выполнить команду не в том каталоге, о
  /// котором думает человек, — худшее, что строка может сделать. В архиве она
  /// приглушена и говорит, почему.
  ///
  /// Приезжает готовым, тем самым, каким назовёт его сама оболочка: на `ssh://`
  /// путь панели — адрес, а оболочка стоит на сервере и про адреса не слышала.
  String? get workingDirectory {
    final directory = panel?.shellDirectory ?? '';
    return directory.isEmpty ? null : directory;
  }

  /// Что показано слева от ввода: путь, в котором всё и произойдёт.
  ///
  /// Вместе с местом, если оно не своя машина: где выполнится набранное, видно
  /// **до** нажатия — иначе `rm` на сервере не отличить от `rm` у себя.
  String get prompt {
    final path = panel?.currentPath ?? '';
    final label = panel?.source.shellLabel ?? '';
    return label.isEmpty || label == 'localhost' ? path : '$label:$path';
  }

  /// Оболочка того места, где стоит панель; null — её ещё не заводили.
  ///
  /// Не заводит новую: показ приглашения — не повод запускать оболочку, она
  /// заводится, когда есть что выполнять.
  TerminalSession? get shell {
    final label = panel?.source.shellLabel ?? '';
    return label.isEmpty ? null : shells?.at(label);
  }

  /// Завести оболочку этого места, если её ещё нет.
  ///
  /// Греется заранее только своя машина: сервер за прогрев при запуске платил
  /// бы походом по сети, а панелей в тот миг ещё нет. Но когда панель **уже
  /// стоит** на сервере, соединение с ним есть, и оболочка обходится одним
  /// каналом — без второго входа и без вопроса о пароле.
  ///
  /// Без этого приглашение сервера не показывалось до первого `Ctrl-O` вовсе:
  /// показывать было нечего (`docs/spec/shell-prompt.md`, §7). Заодно и первый
  /// `Ctrl-O` там открывается сразу.
  ///
  /// **Просит её строка**, а не тот, кто ходит за панелью: показывает
  /// приглашение она, ради показа оболочка и заводится — и настройку
  /// спрашиваем ту же, показа.
  ///
  /// Попытка одна на место: не удалось — молчим и второй раз не пробуем.
  /// Человек терминала не просил, и жаловаться ему не на что; попросит —
  /// узнает тогда.
  void ensureShell() {
    if (!settings.shellPrompt) {
      return;
    }
    final source = panel;
    final label = source?.source.shellLabel ?? '';
    final at = source?.shellDirectory ?? '';
    if (label.isEmpty || at.isEmpty || shells == null || shells!.at(label) != null || !_asked.add(label)) {
      return;
    }
    // С каталогом панели: оболочка обязана начать там, где человек стоит, —
    // иначе первое же приглашение будет про её домашний каталог, а не про его.
    unawaited(shells!.sessionIn(app, panel: source, directory: at).then((_) {}, onError: (_) {}));
  }

  /// Места, для которых оболочку уже просили.
  final Set<String> _asked = {};

  /// Приглашение оболочки; пустое — показываем своё (путь и `$`).
  ///
  /// Пустым оно бывает по трём причинам, и все три законны: настройка
  /// выключена, оболочки этого места ещё нет, оболочка о себе не рассказывает
  /// (уговор не подошёл).
  ShellPrompt get shellPrompt {
    if (!settings.shellPrompt) {
      return ShellPrompt.none;
    }
    final session = shell;
    return session == null || !session.marksWork ? ShellPrompt.none : session.prompt;
  }

  /// Оболочка ещё не там, где панель.
  ///
  /// Показанное приглашение в этот миг — про прежний каталог, и говорить им о
  /// новом нельзя. Строка не прячет его, а приглушает: мигать на каждом шаге
  /// по каталогам она не должна (`docs/spec/shell-prompt.md`, §7).
  bool get shellPromptStale {
    final session = shell;
    if (session == null) {
      return false;
    }
    final at = session.lastMark?.directory ?? '';
    return at.isEmpty || at != workingDirectory;
  }

  /// Строку можно выполнить здесь.
  bool get enabled => workingDirectory != null;

  bool get isEmpty => text.text.trim().isEmpty;

  /// Строка пуста совсем — от этого зависит, кому достанется клавиша в режиме
  /// `mc`: пробел, `Enter` и `Bsp` принадлежат панели, пока в строке ничего нет.
  bool get isBlank => text.text.isEmpty;

  /// Печать уходит сюда, а не в переход к имени (`spec/mc-command-line.md`).
  ///
  /// И только там, где строке есть что делать: на `ssh://` и в архиве она
  /// приглушена, выполнять всё равно нечем — значит и печать туда не уходит.
  bool get typingGoesToLine => settings.typingGoesToLine && enabled;

  /// Дописать в конец — так печатают, когда ввод у панели.
  void append(String value) {
    final updated = text.text + value;
    text.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: updated.length));
    _completion = null;
    notifyListeners();
  }

  /// Стереть последний символ.
  ///
  /// Символ, а не код: составные значки стираются целиком, как в любом поле
  /// ввода.
  void eraseLast() {
    final current = text.text;
    if (current.isEmpty) {
      return;
    }
    final updated = current.characters.skipLast(1).toString();
    text.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: updated.length));
    _completion = null;
    notifyListeners();
  }

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

  // --- дополнение ---

  /// Начатое дополнение; null — подсказки нет.
  CompletionRun? get completion => _completion;
  CompletionRun? _completion;

  /// Кандидаты, которые стоит показать: их больше одного, значит есть из чего
  /// выбирать. Один подставляется молча — показывать нечего.
  List<CompletionCandidate> get suggestions => (_completion?.hasChoice ?? false) ? _completion!.candidates : const [];

  /// Который кандидат подставлен сейчас; -1 — перебор не начинали.
  int get suggestionIndex => _completion?.index ?? -1;

  /// Перебор продолжается: строку с прошлой вставки не трогали.
  bool get isCompleting => _completion?.matches(text.text) ?? false;

  /// Подставляет разобранное: одного кандидата целиком, из многих — общее
  /// начало, а если и его нет — первого, начиная перебор.
  void complete(CompletionToken token, List<CompletionCandidate> candidates) {
    if (candidates.isEmpty) {
      clearCompletion();
      return;
    }

    final run =
        CompletionRun(start: token.start, directory: token.directory, quote: token.quote, candidates: candidates)
          ..typed = text.text
          ..typedCaret = token.end;

    if (candidates.length == 1) {
      _insertCompletion(run, candidates.single.insertion, to: token.end);
      // Выбора больше нет: подставили — и забыли.
      _completion = null;
      notifyListeners();
      return;
    }

    _completion = run;
    final shared = commonPrefix([for (final candidate in candidates) candidate.name]);
    if (shared.length > token.prefix.length) {
      // Есть что дописать без выбора — дописываем и ждём: человек доберёт сам
      // или нажмёт `Tab` ещё раз.
      _insertCompletion(run, shared, to: token.end);
    } else {
      _insertCompletion(run, run.step(forward: true).insertion, to: token.end);
    }
    notifyListeners();
  }

  /// Следующий кандидат по кругу.
  void cycleCompletion({required bool forward}) {
    final run = _completion;
    if (run == null || !run.hasChoice) {
      return;
    }
    _insertCompletion(run, run.step(forward: forward).insertion, to: run.end);
    notifyListeners();
  }

  /// Принять подставленное: выбор закончен, а набранное остаётся.
  ///
  /// Так `Enter` во время выбора не выполняет команду, а закрепляет её кусок:
  /// после `docs/` человек продолжает погружаться, а не запускает `cd docs/`
  /// нечаянно.
  void acceptCompletion() {
    if (_completion == null) {
      return;
    }
    _completion = null;
    notifyListeners();
  }

  /// Отказаться: строка возвращается к тому, что было набрано руками.
  bool cancelCompletion() {
    final run = _completion;
    if (run == null) {
      return false;
    }
    text.value = TextEditingValue(
      text: run.typed,
      selection: TextSelection.collapsed(offset: run.typedCaret.clamp(0, run.typed.length)),
    );
    _completion = null;
    notifyListeners();
    return true;
  }

  void clearCompletion() {
    if (_completion == null) {
      return;
    }
    _completion = null;
    notifyListeners();
  }

  /// Заменяет токен на подставленное и запоминает, где остановились.
  void _insertCompletion(CompletionRun run, String value, {required int to}) {
    final base = text.text;
    final inserted = quotePath('${run.directory}$value');
    final updated = base.replaceRange(run.start, to.clamp(run.start, base.length), inserted);
    final caret = run.start + inserted.length;

    text.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: caret));
    run
      ..end = caret
      ..text = updated;
  }

  void clear() {
    text.clear();
    _cursor = history.length;
    _draft = '';
    _completion = null;
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
    final inserted = _separated(base.substring(0, at)) ? ' $value' : value;

    text.value = TextEditingValue(
      text: base.replaceRange(at, end, inserted),
      selection: TextSelection.collapsed(offset: at + inserted.length),
    );
    notifyListeners();
  }

  /// Нужен ли пробел между уже набранным и вставляемым.
  ///
  /// Только если перед курсором **буква или цифра**, то есть кончилось слово:
  /// `rm` и имя без пробела слиплись бы. А `./`, `--out=`, `/usr/` и кавычка —
  /// это начало самого имени, и пробел там его ломает: набранное `./` и
  /// вставленный файл должны дать `./file`, а не `./ file`.
  static bool _separated(String before) {
    if (before.isEmpty) {
      return false;
    }
    return _wordEnd.hasMatch(before.substring(before.length - 1));
  }

  static final RegExp _wordEnd = RegExp(r'[\p{L}\p{N}]', unicode: true);

  void _show(String line) {
    text.value = TextEditingValue(text: line, selection: TextSelection.collapsed(offset: line.length));
    notifyListeners();
  }

  @override
  void close() => text.dispose();
}
