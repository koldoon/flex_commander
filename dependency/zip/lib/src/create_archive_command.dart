import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'zip_encoding.dart';

/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum ZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 6),
  best('Best', 9);

  const ZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень deflate: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static ZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => ZipCompression.normal);
}

/// Упаковать выбранное в новый zip-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Источники могут лежать где угодно, в том числе в другом архиве: содержимое
/// берётся через [LocalCopySession], а она сама решает, есть ли у файла
/// настоящий путь или его придётся выложить во временный.
class CreateZipArchiveCommand extends AsyncCommandBase {
  CreateZipArchiveCommand({required StagingArea staging}) : _staging = staging;

  static const String commandId = 'zip.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [ZipCompression].
  static const String compressionParam = 'compression';

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка ложится в
  /// архив ссылкой, как в mc.
  static const String followLinksParam = 'followLinks';

  final StagingArea _staging;

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Zip';

  @override
  String get description => 'Pack the selected items into a new zip archive';

  @override
  String get dialogTitle => 'Create ZIP archive';

  /// Окно начинается с формы, и фокус нужен полю имени.
  @override
  bool get dialogTakesFocus => true;

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
  Future<void> execute() async {
    final sources = _sourcesOf(context);
    final destination = context.target.directory;
    if (sources.isEmpty || destination == null || isBusy) {
      return;
    }

    final name = _archiveName;
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw FsError(name, FsErrorKind.invalidName);
    }

    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      // Молча затирать существующий архив нельзя: имя можно поправить прямо
      // в окне и повторить.
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }

    // Аренда обоих концов на всё время работы: упаковку можно отправить в фон,
    // и любая из панелей за это время вправе уйти из своего архива.
    final from = context.panel.leaseProvider();
    final into = context.target.leaseProvider();

    try {
      await runOperation(_pack(sources, destination, name), message: 'Packing…');
    } finally {
      await from?.release();
      await into?.release();
    }

    // Приёмник теперь показывает не то, что на диске: там появился архив.
    await context.target.reload();
  }

  /// Имя архива: пустое расширение дописывается само — команда всё-таки
  /// называется «create zip archive».
  String get _archiveName {
    final typed = (param<String>(nameParam) ?? '').trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.zip') ? typed : '$typed.zip';
  }

  ZipCompression get _compression => ZipCompression.byName(param<String>(compressionParam));

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: zip дописывает оглавление в
  /// конец, и отданный наружу поток пришлось бы держать открытым до последнего
  /// байта — а приёмник вправе и не уметь такого. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  AsyncOperation<void> _pack(List<FsNode> sources, DirectoryNode destination, String name) {
    return TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Packing');
      // Плечи: сперва архив собирается, потом уходит приёмнику. Второе
      // бывает и дольше первого — по сети, например.
      progress.beginStage('packing', index: 1, count: 2);
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final links = _Links(follow: param<bool>(followLinksParam) ?? false);

      final staged = await _staging.open('flex_commander_zip_create');
      final copies = LocalCopySession(_staging, prefix: 'flex_commander_zip_source');
      final archivePath = p.join(staged.path, name);

      try {
        // Сперва обход, потом сжатие — и сжатие в отдельном изоляте.
        //
        // Обход спрашивает провайдеров и человека (про ссылки), а это дело
        // главного изолята: туда не переехать. Зато сжатие туда переезжает
        // целиком — оно синхронное, и на большом дереве кадры не выходят вовсе.
        final entries = <ZipItem>[];
        for (final source in sources) {
          await op.checkpoint();
          progress.startSource(source.name);
          // Объекты и байты считает сам обход: `sourceDoneWholly` здесь
          // добавил бы их второй раз — он для работ, которые проходят источник
          // целиком одним действием.
          await _addNode(entries, source, source.name, copies, op, progress, links);
        }

        await op.checkpoint();

        await encodeZipArchive(
          archivePath: archivePath,
          entries: entries,
          level: _compression.level,
          op: op,
          onEntry: (name, bytes) => progress.startItem(name, bytes: bytes),
          onEntryDone: progress.advance,
          // Байты приходят по мере того, как упаковщик читает запись: так видно
          // движение и внутри одного большого файла, а не только между файлами.
          onBytes: progress.advanceBytes,
        );

        await op.checkpoint();

        // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
        // момента неизвестен, поэтому работа прирастает здесь — бар при этом
        // не прыгает назад, а лишь пересчитывает оставшееся.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing archive', index: 2, count: 2);
        await _deliver(archivePath, destination, name, op, progress);
      } finally {
        progress.stop();
        await copies.purge();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Записывает один объект в список заданий: файл — записью, каталог —
  /// записью и обходом.
  ///
  /// Именно список, а не сам архив: сжатие идёт потом и в другом изоляте.
  Future<void> _addNode(
    List<ZipItem> entries,
    FsNode node,
    String entryName,
    LocalCopySession copies,
    TaskOperation<void> op,
    TransferProgress progress,
    _Links links,
  ) async {
    await op.checkpoint();

    // Ссылка разбирается до того, как узел сочтут файлом: ссылка на каталог
    // файлом не является, и поток по ней не открыть — на этом и падала
    // упаковка каталога с `.framework` внутри.
    if (node is LinkNode) {
      final FsNode? followed = await _addLink(node, op, links);
      if (followed == null) {
        return;
      }
      try {
        await _addNode(entries, followed, entryName, copies, op, progress, links);
      } finally {
        links.leaveLink(node);
      }
      return;
    }

    if (node is DirectoryNode) {
      // Пустой каталог иначе пропал бы: в zip он существует только записью.
      entries.add(ZipItem.directory(entryName));

      for (final child in await node.provider.listChildren(node)) {
        await _addNode(entries, child, '$entryName/${child.name}', copies, op, progress, links);
      }
      return;
    }

    // Настоящий путь берётся как есть, чужой источник выкладывается во
    // временный файл: упаковщику нужен файл, по которому можно ходить, — и
    // ходить он будет из другого изолята, где провайдеров нет вовсе.
    entries.add(ZipItem.file(entryName, await copies.localPathOf(node)));
  }

  /// Что делать со ссылкой: положить записью-ссылкой или пойти по ней.
  ///
  /// Возвращает цель, если решено идти; null — со ссылкой уже разобрались.
  Future<FsNode?> _addLink(LinkNode node, TaskOperation<void> op, _Links links) async {
    if (!links.follow) {
      // Ссылку в архив положить нечем.
      //
      // В zip она хранится файлом с правами UNIX (`S_IFLNK`) и признаком
      // «создано на UNIX» в заголовке. Библиотека `archive` пишет заголовок
      // всегда с признаком MS-DOS, поэтому такую запись не узнал бы даже её
      // собственный распаковщик. Подменять ссылку содержимым цели молча
      // нельзя — спрашиваем, как и при отказах.
      await _askAboutLink(op, node, links, kind: _LinkTrouble.cannotStore);
      return null;
    }

    if (!links.enterLink(node)) {
      // По этой ссылке мы уже идём выше по ветке: `docs/loop → docs`.
      await _askAboutLink(op, node, links, kind: _LinkTrouble.recursive);
      return null;
    }

    final FsNode? followed = await node.resolve().result;
    if (followed == null) {
      links.leaveLink(node);
      await _askAboutLink(op, node, links, kind: _LinkTrouble.broken);
      return null;
    }
    return followed;
  }

  /// Вопрос про ссылку — тот же, что при отказах.
  Future<void> _askAboutLink(TaskOperation<void> op, LinkNode node, _Links links, {required _LinkTrouble kind}) async {
    if (links.skipAll) {
      return;
    }

    final answer = await op.ask(
      OperationRequest(
        message: switch (kind) {
          _LinkTrouble.cannotStore => 'Cannot store the link «${node.name}» in a zip archive',
          _LinkTrouble.recursive => 'The link «${node.name}» points into the directory being packed',
          _LinkTrouble.broken => 'The link «${node.name}» leads nowhere',
        },
        options: const [OperationOption.skip, OperationOption.skipAll, OperationOption.cancel],
        defaultOption: OperationOption.skip,
      ),
    );

    if (answer == OperationOption.cancel) {
      throw const OperationCanceled();
    }
    if (answer == OperationOption.skipAll) {
      links.skipAll = true;
    }
  }

  /// Передаёт готовый архив приёмнику — тем же байтовым контрактом, которым
  /// пользуется движок переноса.
  Future<void> _deliver(
    String archivePath,
    DirectoryNode destination,
    String name,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    final provider = destination.provider;
    if (provider is! FileContentReceiver) {
      throw FsError(destination.pathString, FsErrorKind.notSupported);
    }

    final file = File(archivePath);
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: await file.length());

    try {
      progress
        ..startSource(name)
        ..startItem(name, bytes: await file.length());
      await sink.addStream(
        file.openRead().asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length);
          return chunk;
        }),
      );
      await sink.close();
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
      // Второй проход по тем же байтам — такая же работа, как первый.
      progress.countBytes(bytes);
    }

    progress.countingFinished();
  }

  // --- окно ---

  /// Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
  /// длительных работ: упаковка ничем не отличается от копирования, и
  /// рассказывать о ней иначе незачем. Своё у команды одно — форма.
  @override
  Widget? getDialog(BuildContext context) =>
      AsyncCommandDialog(command: this, form: (context) => _CreateArchiveForm(command: this));

  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String get defaultName {
    final sources = _sourcesOf(context);
    if (sources.length == 1) {
      return '${sources.single.name}.zip';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.zip';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String get destinationPath => context.target.directory?.pathString ?? '';
}

/// Форма создания архива: имя и степень сжатия.
class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.command});

  final CreateZipArchiveCommand command;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _name = TextEditingController(text: widget.command.defaultName);
  late final TextEditingController _destination = TextEditingController(text: widget.command.destinationPath);
  ZipCompression _compression = ZipCompression.normal;

  @override
  void initState() {
    super.initState();
    // Значения задаются сразу, а не при подтверждении: Enter обрабатывает
    // ядро, и к моменту execute параметры уже должны быть на месте.
    widget.command.setParam(CreateZipArchiveCommand.nameParam, _name.text);
    widget.command.setParam(CreateZipArchiveCommand.compressionParam, _compression.name);
  }

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandDialogForm(
      error: widget.command.error,
      onCancel: widget.command.dismiss,
      onSubmit: widget.command.submit,
      submitLabel: 'Create',
      children: [
        CommandDialogField(label: 'Create in', child: FcTextField(controller: _destination, enabled: false)),
        CommandDialogField(
          label: 'Archive name',
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: 'archive.zip',
            onChanged: (value) => widget.command.setParam(CreateZipArchiveCommand.nameParam, value),
            onSubmitted: (_) => widget.command.submit(),
          ),
        ),
        // Ссылки: по умолчанию ложатся в архив ссылками, как в mc.
        FcCheckbox(
          label: 'Follow symlinks',
          value: widget.command.param<bool>(CreateZipArchiveCommand.followLinksParam) ?? false,
          onChanged:
              (value) => setState(() => widget.command.setParam(CreateZipArchiveCommand.followLinksParam, value)),
        ),
        CommandDialogField(
          label: 'Compression',
          child: FcRadioGroup<ZipCompression>(
            direction: Axis.horizontal,
            options: {for (final value in ZipCompression.values) value: value.title},
            value: _compression,
            onChanged: (value) {
              setState(() => _compression = value);
              widget.command.setParam(CreateZipArchiveCommand.compressionParam, value.name);
            },
          ),
        ),
      ],
    );
  }
}

/// Что делать со ссылками при упаковке.
///
/// Своя, а не общая с движком переноса: у движка вопрос «умеет ли приёмник
/// хранить ссылку», а zip умеет всегда — здесь решается только «класть ссылкой
/// или идти по ней».
class _Links {
  _Links({required this.follow});

  /// Дальше этого числа вложенных ссылок не идём: относительные ссылки могут
  /// ходить по кругу, ни разу не повторившись строкой.
  static const int maxDepth = 32;

  final bool follow;

  bool skipAll = false;

  /// Куда ведут ссылки, по которым мы сейчас идём.
  ///
  /// По цели, а не по пути: цель ссылки остаётся ребёнком самой ссылки, и путь
  /// у неё идёт через ссылку — сравнивать пути бесполезно.
  final Set<String> _following = {};

  bool enterLink(LinkNode node) {
    if (_following.length >= maxDepth) {
      return false;
    }
    return _following.add(node.reference);
  }

  void leaveLink(LinkNode node) => _following.remove(node.reference);
}

/// Что не так со ссылкой.
enum _LinkTrouble { cannotStore, recursive, broken }
