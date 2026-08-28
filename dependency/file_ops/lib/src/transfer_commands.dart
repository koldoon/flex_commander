import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

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
    if (target == null || !target.provider.canWrite || (moves && !panel.provider.canWrite)) {
      return false;
    }
    // Псевдоузел «..» объектом не считается.
    return context.targets.any((node) => node is! ParentDirNode);
  }

  /// Объекты, с которыми работает команда: помеченные или тот, что под курсором.
  List<FsNode> targetsOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  /// Пришло ли задание готовым — со своими объектами и приёмником.
  static bool givenJob(CommandContext context) => context.invocation.param<List<String>>(sourcesParam) != null;

  /// Перенести — или сперва спросить, куда.
  ///
  /// Путь задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    // Редактор берётся у приёмника, а не у источника: операцию выполняет
    // движок, один на все провайдеры, и получить его нужно там, где заведомо
    // умеют принимать. У источника его может не быть вовсе — это не мешает
    // копировать из него.
    final destination = _destinationPanelOf(context);
    final editor = destination?.editor;
    final givenSources = context.invocation.param<List<String>>(sourcesParam);
    final targets = targetsOf(context);
    if (editor == null || (givenSources == null && targets.isEmpty)) {
      return;
    }

    Future<void> transfer(TreeEditor editor, String path, bool followLinks, [FcAsyncRun? run]) async {
      final resolved = await _resolveDestination(context, path);
      // Источники приходят путями, и разбирает их та же панель, что и приёмник:
      // путь может вести внутрь архива, который ради этого и смонтируют.
      final sources = <ResolvedNode>[];
      if (givenSources != null) {
        for (final source in givenSources) {
          sources.add(await destination!.resolvePath().run(source));
        }
      }
      final nodes = givenSources == null ? targets : [for (final source in sources) source.node!];
      final destinationNode = resolved.node! as DirectoryNode;
      final operation = moves ? editor.move() : editor.copy();
      final params = TransferParams(nodes, destinationNode, followLinks: followLinks);

      // Аренда источника — на всё время работы, а не на каждое чтение: между
      // чтениями панель успевает уйти, а работа, отправленная в фон,
      // продолжает читать оттуда, откуда она ушла.
      final source = panel.leaseProvider();

      try {
        final message = moves ? 'Moving…' : 'Copying…';
        if (run != null) {
          await run.run(operation, params, message: message);
        } else {
          await operation.run(params);
        }
      } finally {
        // Отпускаются все — и после отмены, и после ошибки: `finally` для того
        // здесь и стоит.
        await resolved.release();
        for (final source in sources) {
          await source.release();
        }
        await source?.release();
        // Обе панели теперь показывают не то, что на диске: в приёмнике
        // объекты появились, из источника при переносе исчезли.
        //
        // Пометку снимает только та работа, которая по ней и шла: задание,
        // пришедшее готовым, о пометке ничего не знает, и стирать чужую
        // разметку ему не за что.
        if (givenSources == null) {
          panel.selection.clear();
        }
        await panel.reload();
        await _reloadDestination(context);
      }
    }

    // «Задан» — значит параметр есть, а не «есть и непустой»: пробелы это
    // заданный приёмник, просто негодный, и сказать об этом надо, а не
    // показывать окно, которого сценарий не увидит.
    final given = context.invocation.param<String>(destinationParam);
    if (given != null) {
      await transfer(editor, given, context.invocation.param<bool>(followLinksParam) ?? false);
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
      // Каталог пассивной панели — разумный ответ на вопрос «куда».
      destination: _defaultDestinationOf(context) ?? '',
    );
    run.onStart = () => transfer(editor, run.destination, run.followLinks, run);

    present();
  }

  /// Каталог-приёмник по пути из параметра — вместе с арендой.
  ///
  /// Аренда здесь не формальность: приёмник задают строкой, и она может вести
  /// не туда, где панель стоит. Тогда архив по дороге монтируется ради этой
  /// работы, и отпустить его, кроме неё, некому.
  Future<ResolvedNode> _resolveDestination(CommandContext context, String raw) async {
    final path = raw.trim();
    if (path.isEmpty) {
      throw const FsError('', FsErrorKind.invalidName);
    }

    // Путь разбирает панель-приёмник: он может проходить через несколько
    // провайдеров («…/archive.zip:zip:/inner»), и одному провайдеру такое
    // не по силам.
    final destination = _destinationPanelOf(context);
    if (destination == null) {
      // Приёмника нет: панель напротив накрыта показом. Дотуда доходят только
      // вызовы со значением — клавиша до этого места не добирается, команда
      // невыполнима.
      throw FsError(path, FsErrorKind.notSupported);
    }
    final resolved = await destination.resolvePath().run(path);
    var node = resolved.node;
    if (node is LinkNode) {
      // Ссылка на каталог — тоже каталог: копировать «в неё» можно.
      node = await node.provider.resolveLink().run(node);
    }
    if (node == null) {
      await resolved.release();
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node is! DirectoryNode) {
      await resolved.release();
      throw FsError(path, FsErrorKind.notADirectory);
    }
    return ResolvedNode(node, resolved.lease);
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

  Future<void> _reloadDestination(CommandContext context) async {
    final panel = _destinationPanelOf(context);
    // Панель могла за это время уйти в другой каталог — перечитывать имеет смысл
    // только то, куда действительно копировали.
    if (panel != null && panel.directory != null) {
      await panel.reload();
    }
  }

  /// Заголовок собирается как в референсе: действие и то, над чем оно идёт.
  String titleOf(CommandContext context) {
    final targets = targetsOf(context);
    final what = targets.length == 1 ? '«${targets.single.name}»' : '${targets.length} items';
    return '$label $what';
  }

  /// Каталог, из которого идёт работа: показывается в окне.
  String _sourcePathOf(CommandContext context) {
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
