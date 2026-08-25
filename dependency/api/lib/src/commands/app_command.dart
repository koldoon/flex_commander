import 'package:flutter/widgets.dart';

import '../app/application.dart';
import '../background/operations.dart';
import '../app/panel.dart';
import '../app/viewport.dart';
import '../tree/fs_node.dart';
import '../tree/tree_provider.dart';
import 'key_combination.dart';

/// Привязка комбинации клавиш к команде.
///
/// Привязка не принадлежит команде: её ставит, хранит и разбирает реестр
/// (`CommandRegistry`). Так их можно будет менять из настроек, не трогая код
/// команд, а сами команды остаются самостоятельными действиями.
class KeyBinding {
  /// Привязка, действующая в файловых панелях.
  ///
  /// Умолчание, потому что клавиша принадлежит тому, что сейчас на экране, а
  /// по умолчанию это панели. Иначе `F5` копировал бы файлы из-под открытого
  /// просмотрщика, а ряд кнопок обещал бы то, чего не будет.
  KeyBinding(String keys, this.commandId, {this.nameMatch, this.parameters = const {}})
    : keys = KeyCombination.parse(keys),
      characterParam = null,
      inContent = _inPanel;

  const KeyBinding.combination(this.keys, this.commandId, {this.nameMatch, this.parameters = const {}})
    : characterParam = null,
      inContent = _inPanel;

  /// Привязка, действующая при содержимом типа [S].
  ///
  /// `KeyBinding.inState<ViewerScreen>('F5', 'text.format')` — «Format / Raw»
  /// в просмотрщике, при том что `F5` в панелях копирует. Именно по
  /// **содержимому**, а не по месту: в полноэкранной области бывает и
  /// просмотрщик, и редактор, и терминал, а одна клавиша значит в них разное.
  static KeyBinding inState<S extends ViewportState>(
    String keys,
    String commandId, {
    RegExp? nameMatch,
    Map<String, Object?> parameters = const {},
  }) => KeyBinding._(
    KeyCombination.parse(keys),
    commandId,
    nameMatch: nameMatch,
    parameters: parameters,
    inContent: (state) => state is S,
  );

  /// Привязка, действующая при любом содержимом.
  static KeyBinding anywhere(String keys, String commandId, {Map<String, Object?> parameters = const {}}) =>
      KeyBinding._(KeyCombination.parse(keys), commandId, parameters: parameters, inContent: null);

  const KeyBinding._(this.keys, this.commandId, {this.nameMatch, this.parameters = const {}, required this.inContent})
    : characterParam = null;

  /// Привязка к любому печатному символу: набранный символ приходит команде
  /// параметром [characterParam].
  ///
  /// Так переход к имени по первой букве обходится одной привязкой вместо
  /// сорока — по одной на каждую клавишу. Команда при этом по-прежнему не знает,
  /// чем её вызвали: символ для неё — обычный параметр, и точно так же его
  /// задаст список команд или сценарий.
  const KeyBinding.anyCharacter(this.commandId, {this.characterParam = 'character', this.parameters = const {}})
    : keys = KeyCombination.anyCharacter,
      nameMatch = null,
      inContent = _inPanel;

  static bool _inPanel(ViewportState state) => state is Panel;

  final KeyCombination keys;

  /// Идентификатор команды ([AppCommand.id]), а не сама команда: привязки
  /// хранятся в настройках, где живут только идентификаторы.
  final String commandId;

  /// Необязательный фильтр по имени объекта под курсором. Позволяет повесить на
  /// Enter разные команды для `*.app`, `*.zip` и обычных файлов — приём
  /// референса (`BindingProperties.nodeValue`). Это условие выбора команды,
  /// а не данные для неё.
  final RegExp? nameMatch;

  /// Значения, с которыми команда выполняется по этой привязке. Позволяет
  /// повесить одну команду на разные клавиши с разными значениями — приём
  /// референса (`BindingProperties.setParams`).
  final Map<String, Object?> parameters;

  /// Имя параметра, в который кладётся набранный символ; null у обычных
  /// привязок.
  final String? characterParam;

  /// Действует ли привязка при таком содержимом активной области;
  /// null — действует при любом.
  final bool Function(ViewportState state)? inContent;

  /// Действует ли привязка сейчас.
  ///
  /// [content] — то, что показано в активной области. null означает, что
  /// области нет **вовсе**: приложение без интерфейса — тест состояния,
  /// сценарий, будущая командная строка. Ограничивать там нечем, и привязка
  /// действует: содержимое — это про то, кому принадлежит клавиша, а не про
  /// то, можно ли выполнить команду.
  bool matches(KeyCombination combination, FsNode? node, {ViewportState? content}) {
    final test = inContent;
    if (test != null && content != null && !test(content)) {
      return false;
    }
    if (keys == KeyCombination.anyCharacter) {
      if (!combination.isCharacter) {
        return false;
      }
    } else if (combination != keys) {
      return false;
    }
    final pattern = nameMatch;
    return pattern == null || (node != null && pattern.hasMatch(node.name));
  }

  /// Значения для запуска по этой комбинации.
  Map<String, Object?> parametersFor(KeyCombination combination) {
    final name = characterParam;
    if (name == null) {
      return parameters;
    }
    return {...parameters, name: combination.key};
  }

  @override
  String toString() => '$keys → $commandId${inContent == null ? ' (везде)' : ''}';
}

/// Условия, в которых выполняется команда: активная панель и объекты, с
/// которыми работать.
///
/// Всё здесь — интерфейсы ([Application], [Panel]): команда работает с API
/// приложения, а не с конкретными контроллерами, и потому не зависит от того,
/// как они устроены.
///
/// Больше в контексте ничего нет намеренно — команда не должна знать, чем её
/// вызвали: клавишей, кнопкой внизу окна или списком команд.
class CommandContext {
  const CommandContext({required this.app, required this.panel, this.node, this.targets = const []});

  final Application app;

  /// Активная панель — источник операции.
  final Panel panel;

  /// Объект под курсором.
  final FsNode? node;

  /// Помеченные объекты, а если пометки нет — объект под курсором.
  /// Именно с этим списком работают файловые операции.
  final List<FsNode> targets;

  /// Пассивная панель — приёмник операций.
  Panel get target => app.passivePanel;
}

/// Как создать действие приложения. Зависимости в фабрику подставляет
/// контейнер.
///
/// Фабрика без аргументов: всё, что команде нужно снаружи, она получает при
/// создании (окружение модуля) и на запуске ([CommandContext]).
typedef AppCommandFactory = AppCommand Function();

/// Значения, с которыми команда выполняется.
///
/// Их можно задать откуда угодно: из окна команды, из меню, из будущей
/// командной строки или из сценария. Аналог `IParameters` референса.
class CommandParameters {
  final Map<String, Object?> _values = {};

  Map<String, Object?> get values => Map.unmodifiable(_values);

  void set(String name, Object? value) => _values[name] = value;

  T? get<T>(String name) {
    final value = _values[name];
    return value is T ? value : null;
  }
}

/// Действие приложения.
///
/// Команда описывает только себя: название, условие выполнимости, поведение —
/// и, если нужно, собственное окно.
///
/// **Каждый запуск — свой экземпляр.** Команда хранит состояние исполнения
/// (что спросили, что уже сделано, где ошибка), поэтому два одновременных
/// запуска не мешают друг другу. Ядро создаёт экземпляр через контейнер и
/// выдаёт ему [runId] — по нему же команда просит закрыть своё окно.
///
/// **Команда не знает, чем её вызвали.** Всё, на что она опирается, — это
/// [CommandContext]: активная панель и выбранные объекты. Ни привязок клавиш,
/// ни места в нижней панели она не объявляет.
///
/// **Окно — вещь необязательная.** Команду можно выполнить и без него: задать
/// параметры через [setParam] и вызвать [execute]. Так её вызовут меню,
/// сценарий или будущая командная строка. Окно только собирает те же самые
/// параметры и вызывает тот же [execute], опираясь на то же API ядра.
///
/// Состояние исполнения меняется через [notifyListeners] — окно команды
/// подписывается на неё обычным `ListenableBuilder` и перерисовывается само.
///
/// **Составлять команды из команд пока нечем, и это намеренно.** Порт
/// командного фреймворка (составные команды, данные между шагами, сроки) в API
/// был, но за всё время им никто не воспользовался, и он ушёл. Когда
/// понадобятся макросы или сценарии, писать их придётся под то, что у команд
/// есть на самом деле: окно, вопросы по ходу работы, фоновый режим и
/// `AsyncOperation` со своей отменой, — а не под общий каркас.
abstract class AppCommand extends ChangeNotifier {
  /// Стабильный идентификатор для настроек, логов и поиска команды в коде:
  /// `panel.open`, `file.copy`. Пользователю не показывается.
  String get id;

  /// Название команды для пользователя: подпись кнопки внизу окна, заголовок
  /// её окна и строка в списке команд. В интерфейсе видно именно его — ни [id],
  /// ни имя класса наружу не показываются.
  String get label;

  /// Что команда делает — одной строкой, для списка команд и справки.
  ///
  /// Пустая строка допустима: у `Cursor up` объяснять нечего, и придумывать
  /// текст ради заполненной колонки незачем.
  String get description => '';

  /// Идентификатор запуска: свой у каждого экземпляра.
  ///
  /// Ядро выдаёт его при создании; по нему команда закрывает своё окно
  /// (`app.closeDialog(runId)`), а ядро отличает окна разных запусков.
  String get runId => _runId;
  String _runId = '';

  /// Условия запуска: активная панель и выбранные объекты.
  /// Ядро передаёт их при создании экземпляра.
  CommandContext get context => _context!;

  /// То же, но без обещания: null — команду вызвали напрямую, минуя ядро.
  /// Так делают тесты, которым приложение не нужно.
  CommandContext? get contextOrNull => _context;
  CommandContext? _context;

  /// Параметры, с которыми команда выполнится.
  final CommandParameters parameters = CommandParameters();

  void setParam(String name, Object? value) => parameters.set(name, value);

  T? param<T>(String name) => parameters.get<T>(name);

  /// Только для ядра: связать экземпляр с запуском.
  void attachRun({required String runId, required CommandContext context}) {
    _runId = runId;
    _context = context;
  }

  /// Заголовок окна команды.
  ///
  /// По умолчанию — [label], но команде бывает что уточнить: «Copy «notes.txt»»
  /// понятнее, чем просто «Copy». В референсе заголовок собирался так же.
  String get dialogTitle => label;

  /// Есть ли у команды окно.
  ///
  /// Если есть, ядро открывает его вместо немедленного выполнения: окно
  /// соберёт параметры и вызовет [execute] само. Если нет — команда
  /// выполняется сразу.
  bool get hasDialog => false;

  /// Над какой частью окна приложения встаёт окно команды.
  ///
  /// По умолчанию — над всем. Команда, работающая с **названной** панелью,
  /// называет её область: «открыть путь в левой» и «открыть путь в правой»
  /// иначе неотличимы на вид.
  DialogArea get dialogArea => DialogArea.window;

  /// Ставит ли окно фокус само — например, в поле ввода.
  ///
  /// Если нет, фокус берёт рама окна: иначе клавиши уходили бы в панели,
  /// а окно осталось бы глухим к Enter и Esc. Явное свойство, а не догадки
  /// по содержимому: кнопки тоже могут принимать фокус, но сами его не просят.
  bool get dialogTakesFocus => false;

  /// Открыто ли сейчас окно этой команды. Выставляет ядро.
  ///
  /// Команда смотрит на это, когда операция задаёт вопрос по ходу работы:
  /// спросить некого, если окна нет, — тогда берётся ответ по умолчанию.
  bool get hasOpenDialog => _hasOpenDialog;
  bool _hasOpenDialog = false;

  /// Только для ядра.
  void setDialogOpen(bool value) => _hasOpenDialog = value;

  /// Можно ли спрятать окно этой команды и оставить работу в фоне.
  ///
  /// Прятать имеет смысл то, что долго идёт и умеет рассказать о себе
  /// ([status]); окно ввода прятать некуда — оно ждёт ответа.
  bool get canRunInBackground => false;

  /// Работа идёт без окна, в общем списке фоновых. Выставляет ядро.
  bool get isInBackground => _isInBackground;
  bool _isInBackground = false;

  /// Только для ядра.
  void setBackground(bool value) => _isInBackground = value;

  /// Содержимое окна команды; null — окно не нужно.
  ///
  /// Рамку, заголовок и затемнение рисует ядро, а что внутри — решает команда:
  /// поля ввода, кнопки, ход выполнения. Виджет подписывается на саму команду,
  /// поэтому меняющееся состояние исполнения он отображает сам.
  ///
  /// Окно — надстройка: оно задаёт те же параметры и вызывает тот же [execute].
  Widget? getDialog(BuildContext context) => null;

  /// Вызывается один раз при установке прототипа. false — команда не
  /// устанавливается (например, недоступна на этой платформе).
  bool init(Application app) => true;

  /// Можно ли выполнить прямо сейчас.
  bool isExecutable(CommandContext context);

  /// Выполняет работу — с параметрами, которые уже заданы, и без вопросов
  /// пользователю. Ошибку сообщает исключением ([FsError]).
  Future<void> execute();

  /// Идёт ли работа.
  ///
  /// Ядро смотрит на это: пока команда исполняется, подтверждение и отмена
  /// в её окне ничего не делают. Команды с длительной работой переопределяют
  /// (см. [AsyncCommand]).
  bool get isRunning => false;

  /// Ошибка последней попытки — её показывает окно команды.
  String? get error => _error;
  String? _error;

  @protected
  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  /// Подтверждение: Enter в открытом окне или кнопка подтверждения.
  ///
  /// Общее поведение для всех команд: выполнить с уже заданными параметрами и
  /// закрыть окно; ошибка остаётся в окне, чтобы можно было исправить ввод
  /// и повторить. Команда может переопределить, если ей нужно иначе.
  Future<void> submit() async {
    if (isRunning) {
      return;
    }
    error = null;

    try {
      await execute();
      closeDialog();
    } on FsError catch (failure) {
      error = failure.message;
    }
  }

  /// Отказ: Esc в открытом окне или кнопка отмены.
  ///
  /// Пока идёт работа, окно не закрывается: прервать её — это отдельное
  /// действие (`AsyncCommand.cancel`).
  void dismiss() {
    if (isRunning) {
      return;
    }
    closeDialog();
  }

  /// Закрывает своё окно, если оно открыто.
  void closeDialog() => _context?.app.closeDialog(runId);

  /// Вызывается при завершении приложения.
  Future<void> shutdown() async {}
}

/// Команда, сообщающая о ходе работы наружу.
///
/// Задел на будущее: ядро сможет спрятать окно команды и оставить её работать
/// в фоне, показывая прогресс рядом с другими фоновыми операциями. Аналог
/// `IAsyncCommand` из референса.
abstract interface class AsyncCommand {
  /// Доля выполненного, 0…1; null — прогресс неопределённый.
  double? get progress;

  /// Что происходит прямо сейчас — короткой строкой.
  String get progressMessage;

  /// Сколько объектов обработано.
  int get processed;

  /// Сколько объектов всего; null — пока неизвестно. Долгие операции считают
  /// это число фоном, поэтому оно появляется не сразу и какое-то время растёт.
  int? get total;

  /// Досчитано ли [total] до конца.
  bool get totalIsFinal;

  /// Сколько байт перенесено.
  int get bytes;

  /// Сколько байт всего; null — объём не известен (удаление в корзину,
  /// источник без размеров). Досчитан ли он, говорит тот же [totalIsFinal].
  int? get totalBytes;

  /// Объект, который обрабатывается прямо сейчас; пустая строка — работа
  /// не разбита на объекты.
  String get itemName;

  /// Сколько байт текущего объекта прошло и сколько в нём всего.
  int get itemBytes;

  int? get itemTotalBytes;

  /// Доля текущего объекта, 0…1; null — показывать нечего.
  double? get itemProgress;

  /// Который этап идёт и чем занят: «2 of 2 — repacking archive».
  ///
  /// null — работа одноплечая, и говорить об этапах нечего. Строка собрана
  /// здесь, а не в окне: как называть плечи, решает тот, кто их завёл.
  String? get stageLabel;

  /// Скорость, байт в секунду; null — считать пока не из чего.
  double? get bytesPerSecond;

  /// Сколько ещё ждать; null — оценить не из чего.
  Duration? get remaining;

  /// Работа идёт.
  bool get isRunning;

  /// Завершение работы: успешное, с ошибкой или отменённое.
  Future<void> get completion;

  /// Прервать работу.
  void cancel();
}

/// Часть окна приложения, над которой встаёт окно команды.
///
/// Доли ширины от левого края: `DialogArea(end: 0.5)` — левая половина.
/// Область задаёт и середину окна, и предел его ширины: окно шире панели над
/// ней не поместится, как ни выравнивай.
@immutable
class DialogArea {
  const DialogArea({this.start = 0, this.end = 1})
    : assert(start >= 0 && start < end && end <= 1, 'Область — доли ширины слева направо');

  /// Всё окно приложения.
  static const DialogArea window = DialogArea();

  final double start;
  final double end;

  double get center => (start + end) / 2;
  double get width => end - start;

  @override
  bool operator ==(Object other) => other is DialogArea && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DialogArea($start…$end)';
}

/// Команда, которая ещё не реализована: клавиша за ней уже закреплена, кнопка
/// внизу окна показана и приглушена. Так связка «кнопка ↔ команда ↔ клавиша»
/// проверяется сейчас, а не переписывается вместе с файловыми операциями.
class PlaceholderCommand extends AppCommand {
  PlaceholderCommand({required this.id, required this.label});

  @override
  String get description => 'Not implemented yet';

  @override
  final String id;

  @override
  final String label;

  @override
  bool isExecutable(CommandContext context) => false;

  @override
  Future<void> execute() async {}
}
