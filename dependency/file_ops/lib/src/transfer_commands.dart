import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'panels_at.dart';

/// Копирование выбранных объектов в другой каталог.
class CopyCommand extends TransferCommandBase {
  static const String commandId = 'file.copy';

  @override
  String get id => commandId;

  @override
  String get label => 'Copy';

  @override
  String get description => 'Copy the selected items to the other panel';

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
  String get label => 'Move';

  @override
  String get description => 'Move the selected items to the other panel';

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
      return sources.isNotEmpty && destination != null && panel.provider.canWrite;
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
    // Псевдоузел «..» объектом не считается.
    return context.targets.any((entry) => !entry.isParent);
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
    if (givenSources == null && context.targets.every((entry) => entry.isParent)) {
      return;
    }

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
        final message = moves ? 'Moving…' : 'Copying…';
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
        // Перечитываются все панели, которые смотрят на эти два каталога —
        // откуда и куда, — и каждая по одному разу: обе могут стоять в одном и
        // том же.
        await reloadPanelsAt(context.app, [
          panel.path,
          // Панель могла за это время уйти в другой каталог: перечитывать имеет
          // смысл только то, куда действительно копировали.
          _destinationPanelOf(context)?.path,
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
      await transfer(given, context.invocation.param<bool>(followLinksParam) ?? false);
      return;
    }

    final view = context.app.view;
    late final _TransferRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: titleOf(context),
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
      title: titleOf(context),
      failureMessage: '$label failed',
      show: present,
      sourcePath: _sourcePathOf(context),
      // Сказанное жестом важнее умолчания: бросили в каталог под курсором —
      // туда и пойдёт, а не в тот, что открыт в панели.
      destination: given ?? _defaultDestinationOf(context) ?? '',
    );
    run.onStart = () => transfer(run.destination, run.followLinks, run);

    present();
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
    final directory = _destinationPanelOf(context)?.directory;
    // Полный путь: приёмник может оказаться внутри архива, и часть про
    // локальную ФС из строки выкидывать нельзя.
    return directory?.pathString;
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  String titleOf(CommandContext context) {
    // Задание могло прийти готовым — тогда считать надо его объекты, а не
    // пометку в панели: у брошенного мышью с ней ничего общего.
    final given = context.invocation.param<List<String>>(sourcesParam);
    if (given != null) {
      final what = given.length == 1 ? '«${_nameOf(given.single)}»' : '${given.length} items';
      return '$label $what';
    }
    final targets = [
      for (final entry in context.targets)
        if (!entry.isParent) entry,
    ];
    final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
    return '$label $what';
  }

  /// Имя объекта из пути — для заголовка работы.
  static String _nameOf(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// Каталог, из которого идёт работа: показывается в окне.
  ///
  /// У готового задания он свой: брошенное мышью приехало откуда угодно — из
  /// соседней панели, из Finder, — и панель-приёмник о нём ничего не знает.
  String _sourcePathOf(CommandContext context) {
    final given = context.invocation.param<List<String>>(sourcesParam);
    if (given != null && given.isNotEmpty) {
      final first = given.first;
      final slash = first.lastIndexOf('/');
      return slash <= 0 ? first : first.substring(0, slash);
    }
    return _panelSourcePathOf(context);
  }

  String _panelSourcePathOf(CommandContext context) {
    final panel = context.panel;
    final directory = panel.directory;
    return directory?.displayPath ?? '';
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
  final String sourcePath;

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

    return CommandDialogForm(
      error: run.error,
      onCancel: run.dismiss,
      onSubmit: run.submit,
      submitLabel: widget.submitLabel,
      // Поля те же, что в референсе: откуда и куда. Зазор между строками
      // ставит сама форма.
      children: [
        CommandDialogField(label: 'From', child: FcTextField(controller: _source, enabled: false)),
        CommandDialogField(
          label: 'To',
          child: FcTextField(
            controller: _destination,
            autofocus: true,
            hintText: 'Destination path',
            onChanged: (value) => run.destination = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        ),
      ],
    );
  }
}
