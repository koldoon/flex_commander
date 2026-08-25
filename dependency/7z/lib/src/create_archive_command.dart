import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'seven_zip_cli.dart';

/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum SevenZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 5),
  best('Best', 9);

  const SevenZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень сжатия: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static SevenZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => SevenZipCompression.normal);
}

/// Упаковать выбранное в новый 7z-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Упаковывает не модуль, а программа, и работать она умеет только с файлами на
/// диске. Поэтому источники, у которых настоящего пути нет (другой архив,
/// сервер), сперва выкладываются во временный каталог — за это приходится
/// платить лишним проходом по байтам, и в ходе работы это видно.
class CreateSevenZipArchiveCommand extends AppCommand {
  CreateSevenZipArchiveCommand({required StagingArea staging, required SevenZipCli cli})
    : _staging = staging,
      _cli = cli;

  static const String commandId = '7z.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [SevenZipCompression].
  static const String compressionParam = 'compression';

  /// Идти ли по символическим ссылкам. По умолчанию нет — и тогда программе
  /// нужен ключ `-snl`: сама по себе она ссылки разыменовывает.
  static const String followLinksParam = 'followLinks';

  final StagingArea _staging;
  final SevenZipCli _cli;

  @override
  String get id => commandId;

  @override
  String get label => 'Mk 7z';

  @override
  String get description => 'Pack the selected items into a new 7z archive';

  String get dialogTitle => 'Create 7z archive';

  /// Окно начинается с формы, и фокус нужен полю имени.

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмник не умеет принимать содержимое.
    final destination = context.target.directory;
    return destination != null && destination.provider.canReceive;
  }

  List<FsNode> _sourcesOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute(CommandContext context) async {
    final sources = _sourcesOf(context);
    final destination = context.target.directory;
    if (sources.isEmpty || destination == null) {
      return;
    }

    Future<void> pack(String typed, SevenZipCompression compression, bool followLinks, [FcAsyncRun? run]) async {
      final name = _withExtension(typed);
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      final provider = destination.provider;
      if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
        // Молча затирать существующий архив нельзя: имя можно поправить прямо
        // в окне и повторить.
        throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
      }

      // Аренда обоих концов на всё время работы: упаковку можно отправить в
      // фон, и любая из панелей за это время вправе уйти из своего архива.
      final from = context.panel.leaseProvider();
      final into = context.target.leaseProvider();

      try {
        final operation = packOperation();
        final params = SevenZipPackParams(
          sources,
          destination,
          name,
          compression: compression,
          followLinks: followLinks,
        );
        if (run != null) {
          await run.run(operation, params, message: 'Packing…');
        } else {
          await operation.run(params);
        }
      } finally {
        await from?.release();
        await into?.release();
      }

      // Приёмник теперь показывает не то, что на диске: там появился архив.
      await context.target.reload();
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await pack(
        given,
        SevenZipCompression.byName(context.invocation.param<String>(compressionParam)),
        context.invocation.param<bool>(followLinksParam) ?? false,
      );
      return;
    }

    final view = context.app.view;
    late final _CreateArchiveRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: dialogTitle,
          takesFocus: true,
          content: FcAsyncRunDialog(run: run, form: (_) => _CreateArchiveForm(run: run)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = _CreateArchiveRun(
      app: context.app,
      commandId: id,
      title: dialogTitle,
      failureMessage: '$label failed',
      show: present,
      name: defaultNameOf(context),
      destinationPath: destinationPathOf(context),
    );
    run.onStart = () => pack(run.name, run.compression, run.followLinks, run);

    present();
  }

  /// Имя архива: пустое расширение дописывается само — команда всё-таки
  /// называется «create 7z archive».
  static String _withExtension(String raw) {
    final typed = raw.trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.7z') ? typed : '$typed.7z';
  }

  /// Упаковка.
  ///
  /// Если приёмник — настоящая файловая система, программа пишет архив прямо на
  /// место: лишнего плеча не появляется вовсе. Иначе архив собирается во
  /// временном файле и уходит приёмнику байтами — как у zip.
  @visibleForTesting
  Operation<SevenZipPackParams, void> packOperation() {
    return TaskOperation<SevenZipPackParams, void>((op, params) async {
      final sources = params.sources;
      final destination = params.destination;
      final name = params.name;
      final compression = params.compression;
      final followLinks = params.followLinks;
      final progress = TransferProgress(op);
      // Плечи: сперва архив собирается, потом уходит приёмнику. Второе
      // бывает и дольше первого — по сети, например.
      progress.beginStage('packing', index: 1, count: 2);
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final direct = destination.provider.capabilities.realFileSystem;
      final staged = await _staging.open('flex_commander_7z_create');
      final archivePath = direct ? p.join(destination.pathString, name) : p.join(staged.path, name);

      try {
        final workingDirectory = await _sourcesRoot(sources, staged, op, progress);

        // Имена уходят списком, а не аргументами: помеченных может быть
        // тысячи, и командная строка такой длины не бывает.
        final list = File(p.join(staged.path, 'sources.txt'));
        await list.writeAsString(sources.map((source) => source.name).join('\n'), encoding: utf8);

        await _run(
          archivePath,
          workingDirectory,
          list.path,
          op,
          progress,
          compression: compression,
          followLinks: followLinks,
        );
        await op.checkpoint();

        if (!direct) {
          // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
          // момента неизвестен, поэтому работа прирастает здесь — бар при этом
          // не прыгает назад, а лишь пересчитывает оставшееся.
          final packed = await File(archivePath).length();
          progress
            ..countBytes(packed)
            ..beginStage('storing archive', index: 2, count: 2);
          await _deliver(archivePath, destination, name, op, progress);
        }
      } on Object {
        // Прерванная работа не должна оставить полуархив на месте назначения.
        if (direct) {
          await File(archivePath).delete().catchError((Object _) => File(archivePath));
        }
        rethrow;
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Каталог, относительно которого программа увидит источники.
  ///
  /// У источников с настоящими путями это каталог самой панели: имена уйдут
  /// относительными, и записи в архиве получатся такими же. У остальных —
  /// временный каталог, куда содержимое приходится выложить: программа умеет
  /// упаковывать только то, что лежит на диске.
  Future<String> _sourcesRoot(
    List<FsNode> sources,
    StagedDirectory staged,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
  ) async {
    final provider = sources.first.provider;
    if (provider.capabilities.realFileSystem) {
      final directory = sources.first.parentDirectory;
      if (directory != null) {
        return provider.pathOf(directory);
      }
    }

    final root = p.join(staged.path, 'sources');
    await Directory(root).create(recursive: true);

    for (final source in sources) {
      await _materialize(source, p.join(root, source.name), op, progress);
    }
    return root;
  }

  /// Выкладывает узел на диск: файл — байтами, каталог — обходом.
  Future<void> _materialize(
    FsNode node,
    String path,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
  ) async {
    await op.checkpoint();

    if (node is DirectoryNode) {
      await Directory(path).create(recursive: true);
      for (final child in await node.provider.listChildren(node)) {
        await _materialize(child, p.join(path, child.name), op, progress);
      }
      return;
    }

    final provider = node.provider;
    if (provider is! FileContentProvider) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    // Выкладывание — это работа сверх упаковки: те же байты пройдут ещё раз.
    // Общий объём растёт здесь, чтобы бар не показывал больше сделанного, чем
    // есть на самом деле.
    progress.countBytes(node.size < 0 ? 0 : node.size);
    final item = progress.startItem(node.name, bytes: node.size < 0 ? null : node.size);

    final file = File(path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    try {
      await sink.addStream(
        (await (provider as FileContentProvider).openRead(node)).asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        }),
      );
    } finally {
      progress.finishItem(item);
      await sink.close();
    }
  }

  /// Зовёт программу и переводит её вывод в ход работы.
  ///
  /// Программа рассказывает о себе строками вида `+ docs/readme.txt` и
  /// ` 42% 7 + docs/readme.txt`. Ни та, ни другая не говорят, сколько байт уже
  /// сжато внутри записи, — поэтому полоса текущего объекта шагает по файлу
  /// целиком. Придумывать движение внутри записи было бы враньём.
  ///
  /// Вывод читается отдельно от ожидания конца: отмену нельзя ставить в
  /// зависимость от того, разговорчива ли программа. Большой файл она жмёт
  /// молча минутами, и всё это время Esc должен работать.
  Future<void> _run(
    String archivePath,
    String workingDirectory,
    String listFile,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required SevenZipCompression compression,
    required bool followLinks,
  }) async {
    final session = await _cli.start([
      'a',
      '-t7z',
      '-mx=${compression.level}',
      '-scsUTF-8',
      // Без него `7z` кладёт в архив содержимое цели вместо самой ссылки.
      if (!followLinks) '-snl',
      SevenZipCli.listSwitch(listFile),
      // Имена обработанных записей и проценты — то единственное, из чего можно
      // собрать ход работы.
      '-bb1',
      '-bsp1',
      '-bso1',
      ..._cli.literalNames,
      '--',
      archivePath,
    ], workingDirectory: workingDirectory);

    final complaints = StringBuffer();
    final watching = session.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach(complaints.write);

    final packing = _PackingProgress(progress, workingDirectory);
    final reading = _read(session.stdout, packing).catchError((Object _) {});

    try {
      final exit = session.exitCode;
      var finished = false;
      unawaited(exit.then((_) => finished = true));

      // Опрос, а не ожидание: `checkpoint` — единственное место, где отмена
      // превращается в вопрос пользователю, и звать его нужно самим.
      while (!finished) {
        await Future.any([exit, Future<void>.delayed(_cancelPollInterval)]);
        if (finished) {
          break;
        }
        await op.checkpoint();
      }

      final code = await exit;
      await reading;
      await watching;

      if (!_cli.succeeded(code)) {
        throw SevenZipCli.errorOf(archivePath, code, complaints.toString());
      }

      packing.finish();
    } finally {
      // Отмена или ошибка: программа, оставшаяся без слушателя, должна
      // остановиться, а не дописывать архив в никуда.
      await session.kill();
      await reading;
    }
  }

  /// Как часто спрашивать, не передумал ли пользователь.
  static const Duration _cancelPollInterval = Duration(milliseconds: 200);

  Future<void> _read(Stream<List<int>> output, _PackingProgress packing) async {
    await for (final line in _lines(output)) {
      final item = sevenZipItemOf(line);
      if (item != null) {
        await packing.startItem(item);
      }
    }
  }

  /// Строки вывода. Ход работы программа печатает через возврат каретки, а не
  /// перевод строки: без разбиения по обоим она выглядела бы одной строкой на
  /// весь архив.
  Stream<String> _lines(Stream<List<int>> source) {
    return source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .expand((line) => line.split('\r'));
  }

  /// Передаёт готовый архив приёмнику — тем же байтовым контрактом, которым
  /// пользуется движок переноса.
  Future<void> _deliver(
    String archivePath,
    DirectoryNode destination,
    String name,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
  ) async {
    final provider = destination.provider;
    if (provider is! FileContentReceiver) {
      throw FsError(destination.pathString, FsErrorKind.notSupported);
    }

    final file = File(archivePath);
    final length = await file.length();
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: length);

    try {
      progress.startSource(name);
      final item = progress.startItem(name, bytes: length);
      await sink.addStream(
        file.openRead().asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        }),
      );
      await sink.close();
      progress.finishItem(item);
    } on Object {
      await sink.close().catchError((Object _) {});
      rethrow;
    }
  }

  Future<void> _count(List<FsNode> sources, TransferProgress progress) async {
    for (var i = 0; i < sources.length; i++) {
      if (progress.stopped) {
        return;
      }

      var counted = 0;
      var bytes = 0;
      try {
        await sources[i].provider.countEntries(sources[i], (size) {
          counted++;
          bytes += size;
          progress.countOne(size);
        });
      } on FsError {
        // Каталог мог исчезнуть или оказаться закрытым — считаем дальше.
      }
      progress.sourceCounted(i, counted, bytes);
    }

    progress.countingFinished();
  }

  // --- окно ---

  /// Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
  /// длительных работ: упаковка ничем не отличается от копирования, и
  /// рассказывать о ней иначе незачем. Своё у команды одно — форма.
  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String defaultNameOf(CommandContext context) {
    final sources = _sourcesOf(context);
    if (sources.length == 1) {
      return '${sources.single.name}.7z';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.7z';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target.directory?.pathString ?? '';
}

/// Ход упаковки: какая запись сейчас в работе и сколько она весит.
///
/// Программа называет запись, когда берётся за неё, — значит, приход имени
/// означает, что предыдущая запись готова. Последняя закрывается уже по концу
/// работы.
class _PackingProgress {
  _PackingProgress(this._progress, this._workingDirectory);

  final TransferProgress _progress;
  final String _workingDirectory;

  String? _current;
  int? _item;
  int _bytes = 0;

  Future<void> startItem(String name) async {
    if (name == _current) {
      return;
    }
    finish();

    _current = name;
    // Размер берётся с диска: программа его не печатает, а один вызов stat
    // рядом со сжатием ничего не стоит.
    _bytes = await _sizeOf(p.join(_workingDirectory, name));
    // Источник задания — тот, из которого запись пришла: он назван первым
    // звеном её пути. Строка `Item` держится на нём, пока по его содержимому
    // бежит `File`.
    final cut = name.indexOf('/');
    _progress.startSource(cut < 0 ? name : name.substring(0, cut));
    _item = _progress.startItem(p.basename(name), bytes: _bytes);
  }

  /// Закрывает текущую запись: объект готов, байты засчитаны.
  void finish() {
    final current = _current;
    if (current == null) {
      return;
    }
    _progress.advanceBytes(_bytes, _item);
    if (_item case final item?) {
      _progress.finishItem(item);
    }
    _progress.advance();
    _current = null;
    _item = null;
    _bytes = 0;
  }

  /// Размер файла на диске; 0 — его нет (каталог, пропавший файл).
  Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }
}

/// Имя записи из строки вывода программы.
///
/// Программа говорит о работе двумя видами строк: `+ docs/readme.txt` при
/// `-bb1` и ` 42% 7 + docs/readme.txt` при `-bsp1`. Имя в них лежит одинаково,
/// поэтому разбор один — и ход работы виден даже там, где какой-то из двух
/// ключей не поддержан.
String? sevenZipItemOf(String line) {
  final match = RegExp(r'(?:^|\s)[+UT=]\s+(\S.*)$').firstMatch(line.trimRight());
  final name = match?.group(1);
  return name == null || name.isEmpty ? null : name;
}

/// Прогон упаковки вместе с тем, что спрашивают до её начала.
class _CreateArchiveRun extends FcAsyncRun {
  _CreateArchiveRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.name,
    required this.destinationPath,
  });

  String name;

  /// Куда ляжет архив. Не редактируется — приёмник задан панелью.
  final String destinationPath;

  /// Ссылки: по умолчанию ложатся в архив ссылками, как в mc.
  bool followLinks = false;

  SevenZipCompression compression = SevenZipCompression.normal;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setCompression(SevenZipCompression value) {
    compression = value;
    notifyListeners();
  }
}

/// Форма создания архива: имя и степень сжатия.
class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.run});

  final _CreateArchiveRun run;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _name = TextEditingController(text: widget.run.name);
  late final TextEditingController _destination = TextEditingController(text: widget.run.destinationPath);

  @override
  void dispose() {
    _name.dispose();
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
      submitLabel: 'Create',
      children: [
        CommandDialogField(label: 'Create in', child: FcTextField(controller: _destination, enabled: false)),
        CommandDialogField(
          label: 'Archive name',
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: 'archive.7z',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        CommandDialogField(
          label: 'Compression',
          child: FcRadioGroup<SevenZipCompression>(
            direction: Axis.horizontal,
            options: {for (final value in SevenZipCompression.values) value: value.title},
            value: run.compression,
            onChanged: run.setCompression,
          ),
        ),
      ],
    );
  }
}

/// Что паковать, куда и как.
class SevenZipPackParams {
  const SevenZipPackParams(
    this.sources,
    this.destination,
    this.name, {
    required this.compression,
    required this.followLinks,
  });

  final List<FsNode> sources;

  /// Каталог, в котором появится архив.
  final DirectoryNode destination;

  /// Имя архива вместе с расширением: `notes.7z`.
  final String name;

  final SevenZipCompression compression;

  /// Идти ли по символическим ссылкам вместо того, чтобы класть их в архив
  /// ссылками.
  final bool followLinks;
}
