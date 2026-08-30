import 'package:flutter/widgets.dart';

import '../app/application.dart';
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
  ///
  /// Печатное берётся из **символа**, а не из имени клавиши: имя приведено к
  /// верхнему регистру и от раскладки не зависит, поэтому набранное `ls` ушло
  /// бы командой как `LS`, а `!` — как `1`. Имя остаётся запасным вариантом для
  /// тех комбинаций, что собраны вручную и символа не несут.
  Map<String, Object?> parametersFor(KeyCombination combination) {
    final name = characterParam;
    if (name == null) {
      return parameters;
    }
    return {...parameters, name: combination.character ?? combination.key};
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
/// Про то, **чем** её вызвали, команда знает ровно одно — [invocation]: клавиша
/// это была, кнопка внизу окна или список команд, из контекста не видно и
/// видно быть не должно.
class CommandContext {
  const CommandContext({
    required this.app,
    required this.panel,
    this.node,
    this.targets = const [],
    this.invocation = const CommandInvocation(),
  });

  /// Условия прямо сейчас.
  ///
  /// Вычисляются, а не хранятся: команда — прототип, она живёт всё время
  /// работы приложения, и запомненный контекст к следующему запуску устарел бы.
  factory CommandContext.of(Application app, [CommandInvocation invocation = const CommandInvocation()]) {
    final panel = app.activePanel;
    final node = panel.currentNode;
    final marked = panel.selection.nodes;

    return CommandContext(
      app: app,
      panel: panel,
      node: node,
      // Если пометки нет, операция работает с объектом под курсором.
      targets: marked.isNotEmpty ? marked : [if (node != null) node],
      invocation: invocation,
    );
  }

  final Application app;

  /// Этот запуск: значения, с которыми команду вызвали.
  ///
  /// Читают его и [AppCommand.isExecutable], и [AppCommand.execute]: «открыть
  /// путь в левой» нельзя, пока левая занята чтением, — а какая именно панель,
  /// известно только из вызова.
  final CommandInvocation invocation;

  /// Активная панель — источник операции.
  final Panel panel;

  /// Объект под курсором.
  final FsNode? node;

  /// Помеченные объекты, а если пометки нет — объект под курсором.
  /// Именно с этим списком работают файловые операции.
  final List<FsNode> targets;

  /// Панель-приёмник: та, что **показана** напротив источника.
  ///
  /// null — напротив панели сейчас нет: её накрыло наложение (быстрый
  /// просмотр, результаты поиска во весь экран). Копировать туда нечего, и
  /// команда становится невыполнимой сама собой — отдельной проверки про
  /// наложения не пишет никто.
  ///
  /// Не `app.passivePanel`: тот отдаёт саму панель, живую под наложением. Она
  /// и правда жива — у неё каталог, курсор и аренда, — но приёмником быть не
  /// может: человек её не видит, и класть файлы туда, куда он не смотрит,
  /// нельзя.
  Panel? get target => app.view.panelAt(app.view.sourceArea.opposite);
}

/// Как создать действие приложения. Зависимости в фабрику подставляет
/// контейнер.
///
/// Фабрика без аргументов: всё, что команде нужно снаружи, она получает при
/// создании (окружение модуля) и на запуске ([CommandContext]).
typedef AppCommandFactory = AppCommand Function();

/// Один запуск команды: с чем её вызвали.
///
/// Отдельным объектом, а не полем команды: команда — прототип, один на всё
/// время работы приложения, и `Cmd+F1` с `Cmd+F2`, нажатые подряд, дали бы два
/// запуска с разными значениями в одном и том же поле.
class CommandInvocation {
  const CommandInvocation({this.parameters = const {}});

  /// Значения запуска: из привязки, из списка команд, из сценария.
  final Map<String, Object?> parameters;

  T? param<T>(String name) {
    final value = parameters[name];
    return value is T ? value : null;
  }
}

/// Действие приложения.
///
/// Команда описывает только себя: название, условие выполнимости, поведение —
/// и, если нужно, собственное окно.
///
/// **Экземпляр один на всё приложение.** Команда — прототип: она отвечает на
/// вопросы о себе (название, выполнимость) и умеет выполниться, но состояния
/// прогона не держит. Что спросили, что уже сделано, где ошибка — это состояние
/// окна ([DialogSpec.content]) или работы ([FcAsyncRun]), и живёт оно там,
/// сколько нужно, хоть в трёх копиях сразу.
///
/// **Команда не знает, чем её вызвали.** Всё, на что она опирается, — это
/// [CommandContext]: активная панель и выбранные объекты. Ни привязок клавиш,
/// ни места в нижней панели она не объявляет.
///
/// **Окно — вещь необязательная.** Команду можно выполнить и без него: назвать
/// значения в [CommandInvocation] и вызвать [execute]. Так её вызовут меню,
/// сценарий или будущая командная строка. Окно только собирает те же самые
/// значения и вызывает тот же [execute], опираясь на то же API ядра.
///
/// **Составлять команды из команд пока нечем, и это намеренно.** Порт
/// командного фреймворка (составные команды, данные между шагами, сроки) в API
/// был, но за всё время им никто не воспользовался, и он ушёл. Когда
/// понадобятся макросы или сценарии, писать их придётся под то, что у команд
/// есть на самом деле: окно, вопросы по ходу работы, фоновый режим и
/// `AsyncOperation` со своей отменой, — а не под общий каркас.
abstract class AppCommand {
  /// Стабильный идентификатор для настроек, логов и поиска команды в коде:
  /// `panel.open`, `file.copy`. Пользователю не показывается.
  String get id;

  /// Название команды для пользователя: подпись кнопки внизу окна, заголовок
  /// её окна и строка в списке команд. В интерфейсе видно именно его — ни [id],
  /// ни имя класса наружу не показываются.
  String get label;

  /// Что команда делает — **одним коротким предложением**: оно стоит и в
  /// справке, и в строке палитры команд, где длинное режется многоточием.
  ///
  /// Пустая строка допустима: у `Cursor up` объяснять нечего, и придумывать
  /// текст ради заполненной колонки незачем.
  String get description => '';

  /// Слова, по которым команду ищут в палитре, но которых нет в [label].
  ///
  /// Заводится не ради полноты: «Mk Tar» умеет `.tar.gz`, и человек, набравший
  /// `gz`, не находил её вовсе — команда есть, делает ровно то, что просят, а
  /// на запрос не отзывается. Название при этом растягивать нельзя: в ряду
  /// кнопок и в заголовке окна видно именно его.
  ///
  /// Не для описания: описание — предложение о деле, а здесь короткие слова,
  /// которые придут в голову вместо названия. Пусто у большинства команд, и
  /// это правильно — синоним нужен там, где название и запрос расходятся.
  Set<String> get keywords => const {};

  /// Приложение, в котором команда установлена; null — её создали в обход
  /// сборки, как делают тесты.
  Application? get appOrNull => _app;
  Application? _app;

  /// Только для ядра: связать команду с приложением.
  ///
  /// Всё остальное команда получает аргументом: условия запуска — в
  /// [CommandContext], который собирает реестр. Приложение хранится только
  /// затем, чтобы модуль мог дотянуться до него в [init] и в своих полях.
  void bind(Application app) => _app = app;

  /// Вызывается один раз при установке прототипа. false — команда не
  /// устанавливается (например, недоступна на этой платформе).
  bool init(Application app) => true;

  /// Можно ли выполнить прямо сейчас.
  bool isExecutable(CommandContext context);

  /// Выполняет работу.
  ///
  /// Значение задано в [CommandContext.invocation] — делаем; не задано —
  /// команда показывает окно и уходит. Первый случай идёт мимо окна вовсе, и
  /// неудачу ему сообщает исключение ([FsError]), а не строка в окне, которого
  /// нет.
  ///
  /// Контекст приходит аргументом, а не полем: он принадлежит запуску, а
  /// команда — прототип и хранить его не вправе.
  Future<void> execute(CommandContext context);

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

/// Окно команды: что в нём, где оно и берёт ли оно фокус.
@immutable
class DialogSpec {
  const DialogSpec({
    required this.title,
    required this.content,
    this.area = DialogArea.window,
    this.takesFocus = false,
    this.onSubmit,
    this.onDismiss,
  });

  /// Заголовок в раме.
  final String title;

  final Widget content;

  /// Над какой частью окна приложения встаёт окно.
  ///
  /// По умолчанию — над всем. Команда, работающая с **названной** панелью,
  /// называет её область: «открыть путь в левой» и «открыть путь в правой»
  /// иначе неотличимы на вид.
  final DialogArea area;

  /// Ставит ли фокус содержимое само — например, в поле ввода.
  ///
  /// Если нет, фокус берёт рама окна: иначе клавиши уходили бы в панели, а
  /// окно осталось бы глухим к Enter и Esc. Явное свойство, а не догадки по
  /// содержимому: кнопки тоже могут принимать фокус, но сами его не просят.
  final bool takesFocus;

  /// Что делает Enter; null — ничего.
  ///
  /// У окна, которым владеет рабочая область, команды за спиной нет: она
  /// показала окно и ушла. Поэтому реакции описываются здесь, вместе с
  /// остальным про это окно.
  final VoidCallback? onSubmit;

  /// Что делает Esc; null — ничего.
  final VoidCallback? onDismiss;
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
  Future<void> execute(CommandContext context) async {}
}
