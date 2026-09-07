import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'panels_at.dart';

/// Копирование выбранных объектов в другой каталог.
class CopyCommand extends TransferCommandBase {
  static const String commandId = 'file.copy';

  @override
  String get id => commandId;

  @override
  String get label => tr('Copy');

  @override
  String get description => tr('Copy the selected items to the other panel');

  @override
  bool get moves => false;
}

/// Перенос выбранных объектов в другой каталог.
///
/// Отдельная команда, а не параметр [CopyCommand]: у неё своя клавиша, своя
/// кнопка и своя строка в списке команд.
class MoveCommand extends TransferCommandBase {
  static const String commandId = 'file.move';

  @override
  String get id => commandId;

  @override
  String get label => tr('Move');

  @override
  String get description => tr('Move the selected items to the other panel');

  /// `rename` в синонимах **нет**, хотя в коммандерах `F6` переименовывает:
  /// приёмником здесь может быть только каталог, и другого имени команде не
  /// задать. Привести человека к ней по этому слову значило бы соврать —
  /// переименования в приложении пока нет вовсе.
  @override
  Set<String> get keywords => const {'relocate', 'transfer'};

  @override
  bool get moves => true;
}

/// Общий ход копирования и переноса.
///
/// Куда переносить — обычный параметр [destinationParam] со строкой пути.
/// По умолчанию это каталог пассивной панели: привычное поведение двухпанельного
/// менеджера. Значение можно заменить — из окна команды или откуда угодно ещё,
/// потому что путь берётся из параметра, а не из панели.
///
/// [execute] делает работу без вопросов о самом задании: что копировать и куда,
/// уже решено. Вопросы по ходу («такой файл уже есть») задаёт операция, и на них
/// отвечает окно, а если окна нет — берётся ответ по умолчанию.
abstract class TransferCommandBase extends AppCommand {
  /// Путь каталога, куда идёт работа.
  static const String destinationParam = 'destination';

  /// Что переносить — списком путей.
  ///
  /// Пусто — как раньше: помеченное в активной панели или объект под курсором.
  /// Задано — задание пришло **готовым**, и панели тут ни при чём: так работает
  /// перетаскивание мышью, где и объекты, и приёмник указаны жестом
  /// (`spec/drag-and-drop.md`, §5).
  ///
  /// Путями, а не узлами, по той же причине, по какой путём задан приёмник: их
  /// разбирает панель через всю цепочку провайдеров, и аренда всего, что ради
  /// этого смонтируют, достаётся команде — той, что доживёт до конца работы.
  static const String sourcesParam = 'sources';

  /// Идти ли по символическим ссылкам.
  ///
  /// По умолчанию нет — как в mc: ссылка переносится ссылкой. Приёмник,
  /// который так не умеет, вызывает вопрос: подменять ссылку её содержимым
  /// молча нельзя, это разные вещи и по размеру, и по смыслу.
  static const String followLinksParam = 'followLinks';

  /// Убирается ли исходный объект.
  bool get moves;

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    if (panel.busy) {
      return false;
    }
    // Задание пришло готовым: что переносить и куда — уже решено, и судить
    // надо по нему, а не по панелям. Иначе бросок мышью в панель зависел бы от
    // того, где стоит курсор в соседней.
    final sources = context.invocation.param<List<String>>(sourcesParam);
    if (sources != null) {
      final destination = context.invocation.param<String>(destinationParam);
      return sources.isNotEmpty && destination != null && panel.source.canWrite;
    }
    // Принимать должен приёмник; терять объекты источник обязан только при
    // переносе — копировать из архива, открытого на просмотр, ничто не мешает.
    // Приёмника может не быть вовсе: напротив стоит не панель, а показ
    // (быстрый просмотр). Копировать туда нечего — того, что видит человек,
    // файлы не примут.
    final target = context.target;
    // Занятая цель принять ничего не может: она сама сейчас читает. Проверять
    // надо обе панели — источник проверен выше, а копируем мы в соседнюю.
    if (target == null || target.busy || !target.source.canWrite || (moves && !panel.source.canWrite)) {
      return false;
    }
    // Помеченное считается **всё**, где бы оно ни лежало: пометить можно и из
    // дерева, в соседней ветви, и клавиша от этого умирать не должна
    // (`docs/spec/operation-targets.md`, §1).
    return panel.hasTargets;
  }

  /// Над чем работать — именем набора: разворачивает его ядро.
  ///
  /// Задание, пришедшее готовым, приносит свои пути: их разбирает корень
  /// дерева, а не панель, — путь пришёл со стороны и к тому месту, где стоит
  /// панель, отношения не имеет.
  Targets targetsOf(CommandContext context) {
    final given = context.invocation.param<List<String>>(sourcesParam);
    return given == null ? Targets.marked(context.panel.id) : Targets.paths(given);
  }

  /// Пришло ли задание готовым — со своими объектами и приёмником.
  static bool givenJob(CommandContext context) => context.invocation.param<List<String>>(sourcesParam) != null;

  /// Перенести — или сперва спросить, куда.
  ///
  /// Путь задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    // Приёмник нужен и для проверки, и для разбора пути: путь может проходить
    // через несколько источников, и разбирает его та панель, которая там
    // стоит. Движок при этом берёт ядро — у приёмника, где заведомо умеют
    // принимать.
    final destination = _destinationPanelOf(context);
    final givenSources = context.invocation.param<List<String>>(sourcesParam);
    if (destination == null || !destination.source.canWrite) {
      return;
    }
    if (givenSources == null && !panel.hasTargets) {
      return;
    }

    // Каталоги, из которых идёт работа. Спрашиваются **до** её начала: после
    // переноса объектов там уже нет, и спросить их каталог будет не у кого
    // (`docs/spec/operation-targets.md`, §6).
    final sources = <String>{};

    Future<void> transfer(String path, bool followLinks, [FcAsyncRun? run]) async {
      // Всё, что раньше делала команда — разбор пути приёмника, разбор
      // исходных путей, аренда источника и приёмника на время работы, — теперь
      // делает ядро: там живут узлы, и там же работа идёт
      // (`docs/spec/client-server.md`, §5.4).
      final spec = OperationSpec(
        kind: moves ? FileOperations.move : FileOperations.copy,
        targets: targetsOf(context),
        destination: destination.id,
        destinationPath: path,
        options: {FileOperations.followLinks: followLinks},
      );

      try {
        final message = moves ? tr('Moving…') : tr('Copying…');
        final operation = context.app.runOperation();
        if (run != null) {
          await run.run(operation, spec, message: message);
        } else {
          await operation.run(spec);
        }
      } finally {
        // Обе панели теперь показывают не то, что на диске: в приёмнике
        // объекты появились, из источника при переносе исчезли.
        //
        // Пометку снимает только та работа, которая по ней и шла: задание,
        // пришедшее готовым, о пометке ничего не знает, и стирать чужую
        // разметку ему не за что.
        if (givenSources == null) {
          panel.clearMarks();
        }
        // Перечитываются все панели, которые смотрят на задетые каталоги —
        // откуда и куда, — и каждая по одному разу: обе могут стоять в одном и
        // том же. Каталогов-источников бывает несколько: помеченное приходит и
        // из соседних ветвей дерева (`docs/spec/operation-targets.md`, §6).
        await reloadPanelsAt(context.app, [
          ...sources,
          panel.currentPath,
          // Панель могла за это время уйти в другой каталог: перечитывать имеет
          // смысл только то, куда действительно копировали.
          _destinationPanelOf(context)?.currentPath,
        ]);
      }
    }

    // «Задан» — значит параметр есть, а не «есть и непустой»: пробелы это
    // заданный приёмник, просто негодный, и сказать об этом надо, а не
    // показывать окно, которого сценарий не увидит.
    final given = context.invocation.param<String>(destinationParam);
    // Приёмник из сценария — молча: параметром зовут не люди, и окно там
    // некому смотреть. Приёмник от мыши — с окном, и **не начиная работу**:
    // жест говорит, что и куда, но не «поехали». Дальше всё как по `F5` —
    // человек видит приёмник, может поменять его, включить проход по ссылкам и
    // сам нажать «Copy». Жест здесь ровно то же, что нажатая клавиша.
    if (given != null && !givenJob(context)) {
      sources.addAll(await _sourceDirectoriesOf(context));
      await transfer(given, context.invocation.param<bool>(followLinksParam) ?? false);
      return;
    }

    final view = context.app.view;
    late final _TransferRun run;
    // Один раз: `present` зовут ещё и при возврате работы из фона, а панель за
    // это время уходит куда угодно — заголовок обязан остаться тем же.
    final title = titleOf(context);

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: title,
          takesFocus: true,
          // Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
          // длительных работ, их берёт на себя окно. Своё здесь одно: куда.
          content: FcAsyncRunDialog(run: run, form: (_) => _TransferForm(run: run, submitLabel: label)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = _TransferRun(
      app: context.app,
      commandId: id,
      title: title,
      failureMessage: '$label failed',
      show: present,
      sourcePath: _sourcePathOf(context),
      // Сказанное жестом важнее умолчания: бросили в каталог под курсором —
      // туда и пойдёт, а не в тот, что открыт в панели.
      destination: given ?? _defaultDestinationOf(context) ?? '',
    );
    run.onStart = () => transfer(run.destination, run.followLinks, run);

    present();
    // Окно уже стоит — теперь можно и спросить, откуда на самом деле цели
    // (`docs/spec/operation-targets.md`, §2).
    unawaited(
      _sourceDirectoriesOf(context).then((directories) {
        sources.addAll(directories);
        run.setSourcePath(_sourcesText({...directories}, run.sourcePath));
      }),
    );
  }

  /// Панель, в которую идёт работа: та, что показана напротив источника.
  /// null — напротив не панель, и работать не с чем.
  /// Куда идёт работа.
  ///
  /// Обычно это панель напротив — привычка двухпанельного менеджера. Но когда
  /// задание пришло готовым (перетаскивание), приёмник — **та панель, в которую
  /// бросили**: она же активная, и панель напротив тут ни при чём.
  Panel? _destinationPanelOf(CommandContext context) => givenJob(context) ? context.panel : context.target;

  String? _defaultDestinationOf(CommandContext context) {
    // Полный путь: приёмник может оказаться внутри архива, и часть про
    // локальную ФС из строки выкидывать нельзя.
    return _destinationPanelOf(context)?.currentPath;
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  ///
  /// Считается по **путям** целей: помеченное бывает из разных каталогов, и
  /// строк своего списка на всех не хватит — а пути приезжают полными
  /// (`docs/spec/operation-targets.md`, §2). Задание, пришедшее готовым, несёт
  /// свои пути, и обе ветви сходятся в одном счёте.
  String titleOf(CommandContext context) => '$label ${_whatOf(context)}';

  String _whatOf(CommandContext context) {
    final paths = pathsOf(context);
    if (paths.length == 1) {
      // Имя берётся у видимой строки, а её нет — последним звеном пути: у
      // помеченного в соседней ветви значения по эту сторону не лежит.
      final path = paths.single;
      final seen = context.panel.entries.where((entry) => entry.path == path).firstOrNull;
      return '«${seen?.name ?? _nameOf(path)}»';
    }
    return plural(paths.length, one: '{n} item', other: '{n} items');
  }

  /// Пути целей: у готового задания свои, иначе — пометка панели.
  static List<String> pathsOf(CommandContext context) =>
      context.invocation.param<List<String>>(sourcesParam) ?? context.panel.targetPaths.toList();

  /// Имя объекта из пути — для заголовка работы.
  static String _nameOf(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// Каталог, из которого идёт работа: показывается в окне сразу.
  ///
  /// Каталог панели — то, что известно **немедленно**; настоящие каталоги целей
  /// приезжают следом, [_tellSources] их и подставит. Окно при этом уже стоит:
  /// ждать ядро до показа нельзя (`docs/spec/operation-targets.md`, §2).
  ///
  /// У готового задания каталог свой: брошенное мышью приехало откуда угодно —
  /// из соседней панели, из Finder, — и панель-приёмник о нём ничего не знает.
  /// Пути там от системы, значений у них нет, и каталог отделяется строкой.
  String _sourcePathOf(CommandContext context) {
    final given = context.invocation.param<List<String>>(sourcesParam);
    if (given != null && given.isNotEmpty) {
      return _sourcesText({for (final path in given) _directoryOf(path)}, context.panel.currentPath);
    }
    return context.panel.currentPath;
  }

  /// Каталоги, из которых идёт работа.
  ///
  /// Значениями от ядра: каталог цели приезжает готовым
  /// (`FileEntry.directoryPath`), и резать путь строкой не надо — разделители у
  /// источника свои. Готовое задание — исключение: там пути от системы, и
  /// значений у них нет вовсе.
  ///
  /// Спрашивается **после** показа окна: ждать оборот границы до `showDialog`
  /// значит оставить щель, в которую провалится удержанная клавиша
  /// (`docs/spec/operation-targets.md`, §2).
  Future<Set<String>> _sourceDirectoriesOf(CommandContext context) async {
    final given = context.invocation.param<List<String>>(sourcesParam);
    if (given != null) {
      return {for (final path in given) _directoryOf(path)};
    }
    return {for (final entry in await context.panel.allTargets()) entry.directoryPath};
  }

  /// Один каталог — он и написан; несколько — их число: перечислять негде, а
  /// сказать правду надо.
  String _sourcesText(Set<String> directories, String fallback) {
    directories.remove('');
    return switch (directories.length) {
      0 => fallback,
      1 => directories.single,
      _ => plural(directories.length, one: '{n} source', other: '{n} sources'),
    };
  }

  static String _directoryOf(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash <= 0 ? trimmed : trimmed.substring(0, slash);
  }
}

/// Прогон переноса вместе с тем, что спрашивают до его начала.
///
/// Куда и идти ли по ссылкам — свойства этого окна, а не команды: команда
/// показала его и ушла.
class _TransferRun extends FcAsyncRun {
  _TransferRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.sourcePath,
    required this.destination,
  });

  /// Откуда идёт работа. Не редактируется — источник задан выбором в панели.
  ///
  /// Меняется один раз: окно встаёт с каталогом панели, а настоящие каталоги
  /// целей приезжают следом (`docs/spec/operation-targets.md`, §5).
  String sourcePath;

  void setSourcePath(String value) {
    if (value == sourcePath) {
      return;
    }
    sourcePath = value;
    notifyListeners();
  }

  String destination;

  /// Идти ли по символическим ссылкам.
  ///
  /// По умолчанию нет — как в mc: ссылка переносится ссылкой.
  bool followLinks = false;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }
}

/// Два поля — откуда и куда — и признак «идти по ссылкам».
class _TransferForm extends StatefulWidget {
  const _TransferForm({required this.run, required this.submitLabel});

  final _TransferRun run;
  final String submitLabel;

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  late final TextEditingController _source = TextEditingController(text: widget.run.sourcePath);
  late final TextEditingController _destination = TextEditingController(text: widget.run.destination);

  @override
  void dispose() {
    _source.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    // «Откуда» дописывается после показа окна: настоящие каталоги целей
    // приезжают от ядра (`docs/spec/operation-targets.md`, §5). Поле выключено,
    // и подменить в нём текст можно без оглядки на курсор и выделение.
    if (_source.text != run.sourcePath) {
      _source.text = run.sourcePath;
    }

    return CommandDialogForm(
      error: run.error,
      onCancel: run.dismiss,
      onSubmit: run.submit,
      submitLabel: widget.submitLabel,
      // Поля те же, что в референсе: откуда и куда. Зазор между строками
      // ставит сама форма.
      children: [
        CommandDialogField(label: context.strings.tr('From'), child: FcTextField(controller: _source, enabled: false)),
        CommandDialogField(
          label: context.strings.tr('To'),
          child: FcTextField(
            controller: _destination,
            autofocus: true,
            hintText: context.strings.tr('Destination path'),
            onChanged: (value) => run.destination = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(
            label: context.strings.tr('Follow symlinks'),
            value: run.followLinks,
            onChanged: run.setFollowLinks,
          ),
        ),
      ],
    );
  }
}
