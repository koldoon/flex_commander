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
class CreateZipArchiveCommand extends AppCommand {
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

  /// Ищут упаковщик и по делу, а не только по формату: «archive», «compress»,
  /// «pack» — слова, которые приходят в голову раньше, чем `zip`.
  @override
  Set<String> get keywords => const {'archive', 'compress', 'pack'};

  String get dialogTitle => 'Create ZIP archive';

  /// Окно начинается с формы, и фокус нужен полю имени.

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмника нет вовсе (панель накрыта показом)
    // или он не умеет принимать содержимое.
    final destination = context.target?.directory;
    return destination != null && destination.provider.canReceive;
  }

  List<FsNode> _sourcesOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  /// Упаковать — или сперва спросить, как назвать и как жать.
  ///
  /// Имя задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final sources = _sourcesOf(context);
    final target = context.target;
    final destination = target?.directory;
    if (sources.isEmpty || target == null || destination == null) {
      return;
    }

    Future<void> pack(String typed, ZipCompression compression, bool followLinks, [FcAsyncRun? run]) async {
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
      final into = target.leaseProvider();

      try {
        final operation = packOperation();
        final params = ZipPackParams(sources, destination, name, compression: compression, followLinks: followLinks);
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
      await target.reload();
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await pack(
        given,
        ZipCompression.byName(context.invocation.param<String>(compressionParam)),
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
  /// называется «create zip archive».
  static String _withExtension(String raw) {
    final typed = raw.trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.zip') ? typed : '$typed.zip';
  }

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: zip дописывает оглавление в
  /// конец, и отданный наружу поток пришлось бы держать открытым до последнего
  /// байта — а приёмник вправе и не уметь такого. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  @visibleForTesting
  Operation<ZipPackParams, void> packOperation() {
    return TaskOperation<ZipPackParams, void>((op, params) async {
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

      final links = _Links(follow: followLinks);

      final staged = await _staging.open('flex_commander_zip_create');
      final copies = LocalCopySession(_staging, prefix: 'flex_commander_zip_source');
      final archivePath = p.join(staged.path, name);

      try {
        // Сперва обход, потом сжатие — и сжатие в отдельном изоляте.
        //
        // Обход спрашивает провайдеров и человека (про ссылки), а это дело
        // главного изолята: туда не переехать. Зато сжатие туда переезжает
        // целиком — оно синхронное, и на большом дереве кадры не выходят вовсе.
        // Метка записи, которую упаковщик держит в работе: он идёт по одной,
        // но байты и её конец приходят разными вызовами.
        int? entryItem;

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
          level: compression.level,
          op: op,
          onEntry: (name, bytes) {
            // Источник задания — тот, из которого запись пришла: он назван
            // первым звеном её пути. Строка `Item` держится на нём, пока по
            // его содержимому бежит `File`.
            progress.startSource(_sourceOf(name));
            entryItem = progress.startItem(name, bytes: bytes);
          },
          onEntryDone: (_) {
            if (entryItem != null) {
              progress.finishItem(entryItem!);
              entryItem = null;
            }
            progress.advance();
          },
          // Байты приходят по мере того, как упаковщик читает запись: так видно
          // движение и внутри одного большого файла, а не только между файлами.
          onBytes: (bytes) => progress.advanceBytes(bytes, entryItem),
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
    TaskOperation<Object?, void> op,
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
  Future<FsNode?> _addLink(LinkNode node, TaskOperation<Object?, void> op, _Links links) async {
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
  Future<void> _askAboutLink(
    TaskOperation<Object?, void> op,
    LinkNode node,
    _Links links, {
    required _LinkTrouble kind,
  }) async {
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
        options: const [OperationRequestOption.skip, OperationRequestOption.skipAll, OperationRequestOption.cancel],
        enterOption: OperationRequestOption.skip,
      ),
    );

    if (answer == OperationRequestOption.cancel) {
      throw const OperationCanceled();
    }
    if (answer == OperationRequestOption.skipAll) {
      links.skipAll = true;
    }
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
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: await file.length());

    try {
      progress.startSource(name);
      final item = progress.startItem(name, bytes: await file.length());
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
      // Второй проход по тем же байтам — такая же работа, как первый.
      progress.countBytes(bytes);
    }

    progress.countingFinished();
  }

  /// Источник, из которого пришла запись архива: первое звено её пути.
  ///
  /// Записи именуются от источника (`docs/nested/deep.txt`), и по имени видно,
  /// чей это объект, — упаковщику знать про источники незачем.
  String _sourceOf(String entry) {
    final cut = entry.indexOf('/');
    return cut < 0 ? entry : entry.substring(0, cut);
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
      return '${sources.single.name}.zip';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.zip';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target?.directory?.pathString ?? '';
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

  ZipCompression compression = ZipCompression.normal;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setCompression(ZipCompression value) {
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
            hintText: 'archive.zip',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        ),
        CommandDialogField(
          label: 'Compression',
          child: FcRadioGroup<ZipCompression>(
            direction: Axis.horizontal,
            options: {for (final value in ZipCompression.values) value: value.title},
            value: run.compression,
            onChanged: run.setCompression,
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

/// Что паковать, куда и как.
class ZipPackParams {
  const ZipPackParams(
    this.sources,
    this.destination,
    this.name, {
    required this.compression,
    required this.followLinks,
  });

  final List<FsNode> sources;

  /// Каталог, в котором появится архив.
  final DirectoryNode destination;

  /// Имя архива вместе с расширением: `notes.zip`.
  final String name;

  final ZipCompression compression;

  /// Идти ли по символическим ссылкам вместо того, чтобы класть их в архив
  /// ссылками.
  final bool followLinks;
}
