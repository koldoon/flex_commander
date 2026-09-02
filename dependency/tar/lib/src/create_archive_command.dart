import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'archive_output.dart';
import 'tar_writer.dart';

/// Что получится на выходе.
///
/// Выбор из двух, а не степень сжатия: у tar её нет вовсе — сжимает не он, а
/// gzip поверх него, и уровень там почти ни на что не влияет.
enum TarFormat {
  plain('.tar', 'tar'),
  gzip('.tar.gz', 'tar.gz'),

  /// То же, что [gzip], и отличается только именем файла.
  ///
  /// Отдельным пунктом, а не догадкой по набранному расширению: `.tgz` живёт
  /// там, где длинные имена неудобны, и человек, которому нужен именно он,
  /// иначе получал бы `.tar.gz` молча.
  tgz('.tgz', 'tgz');

  const TarFormat(this.extension, this.title);

  /// Чем кончается имя архива.
  final String extension;

  /// Название для человека.
  final String title;

  /// Заворачивается ли архив в gzip. У `.tar` — нет, у остальных — да.
  bool get compressed => this != TarFormat.plain;

  static TarFormat byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => TarFormat.gzip);
}

/// Расширения, которые считаются уже написанным именем архива.
///
/// Порядок важен: `.tar.gz` длиннее `.tar` и потому проверяется раньше — иначе
/// от `src.tar.gz` отрезалось бы только `.gz`.
const List<String> _tarExtensions = ['.tar.gz', '.tgz', '.tar'];

/// Упаковать выбранное в новый tar-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Клавиши команде не досталось: `Shift-F5` занял zip, `Shift-F7` — 7z, а
/// `Shift-F6` встал бы поперёк привычки — `F6` в коммандерах это перенос.
/// Команда живёт в палитре, ровно тот случай, ради которого палитра и
/// заводилась.
class CreateTarArchiveCommand extends AppCommand {
  CreateTarArchiveCommand({required StagingArea staging}) : _staging = staging;

  static const String commandId = 'tar.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Формат — имя значения [TarFormat].
  static const String formatParam = 'format';

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка ложится в
  /// архив ссылкой — tar это умеет, и ради этого им и пользуются.
  static const String followLinksParam = 'followLinks';

  final StagingArea _staging;

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Tar';

  @override
  String get description => 'Pack the selected items into a new tar, tar.gz or tgz archive';

  /// Ищут её и по тому, что она умеет: `.tar.gz` в названии не помещается, а
  /// набирают в палитре чаще всего именно `gz`.
  @override
  Set<String> get keywords => const {'tar.gz', 'tgz', 'gzip', 'archive', 'compress', 'pack'};

  String get dialogTitle => 'Create TAR archive';

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмника нет вовсе (панель накрыта показом)
    // или он не умеет принимать содержимое.
    // Занятый приёмник принять ничего не может: он сам сейчас читает.
    final target = context.target;
    final destination = target?.directory;
    return target != null && !target.busy && destination != null && destination.provider.canReceive;
  }

  List<FsNode> _sourcesOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute(CommandContext context) async {
    final sources = _sourcesOf(context);
    final target = context.target;
    final destination = target?.directory;
    if (sources.isEmpty || target == null || destination == null) {
      return;
    }

    Future<void> pack(String typed, TarFormat format, bool followLinks, [FcAsyncRun? run]) async {
      final name = withExtension(typed, format);
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
        final params = TarPackParams(sources, destination, name, format: format, followLinks: followLinks);
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
        TarFormat.byName(context.invocation.param<String>(formatParam)),
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
    run.onStart = () => pack(run.name, run.format, run.followLinks, run);

    present();
  }

  /// Имя архива вместе с расширением выбранного формата.
  ///
  /// Расширение не приписывается, а **заменяется**: набранное имя может уже
  /// кончаться архивным расширением — своим или чужим. Иначе `src.tar.gz` при
  /// том же формате стало бы `src.tar.gz.tar.gz`, а при переключении на `.tgz`
  /// — `src.tar.gz.tgz`, то есть именем, которое врёт о содержимом.
  @visibleForTesting
  static String withExtension(String raw, TarFormat format) {
    final typed = withoutExtension(raw);
    return typed.isEmpty ? '' : '$typed${format.extension}';
  }

  /// Имя без архивного расширения, каким бы из трёх оно ни было.
  @visibleForTesting
  static String withoutExtension(String raw) {
    final typed = raw.trim();
    final lower = typed.toLowerCase();
    for (final suffix in _tarExtensions) {
      if (lower.endsWith(suffix)) {
        return typed.substring(0, typed.length - suffix.length);
      }
    }
    return typed;
  }

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: размер архива до конца работы
  /// неизвестен, а приёмник вправе его требовать. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  ///
  /// Сжатие идёт **в один проход**: gzip навешивается на тот же поток, которым
  /// собирается tar, и промежуточного несжатого файла не появляется.
  @visibleForTesting
  Operation<TarPackParams, void> packOperation() {
    return TaskOperation<TarPackParams, void>((op, params) async {
      final sources = params.sources;
      final destination = params.destination;
      final progress = TransferProgress(op);
      // Плечи: сперва архив собирается, потом уходит приёмнику. Второе бывает
      // и дольше первого — по сети, например.
      progress.beginStage('packing', index: 1, count: 2);
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final staged = await _staging.open('flex_commander_tar_create');
      final archivePath = p.join(staged.path, params.name);
      int? entryItem;

      try {
        final items = _itemsOf(sources, op, progress, followLinks: params.followLinks);
        final bytes = writeTarStream(
          items,
          checkpoint: op.checkpoint,
          onEntry: (item) {
            progress.startSource(_sourceOf(item.name));
            entryItem = progress.startItem(item.name, bytes: item.size);
          },
          // Байты приходят по мере того, как читается запись: так видно
          // движение и внутри одного большого файла, а не только между ними.
          onBytes: (count) => progress.advanceBytes(count, entryItem),
        );

        final out = params.format.compressed ? gzip.encoder.bind(bytes) : bytes;
        final sink = File(archivePath).openWrite();
        try {
          await sink.addStream(out);
        } finally {
          await sink.close();
        }

        await op.checkpoint();

        // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
        // момента неизвестен, поэтому работа прирастает здесь — бар при этом не
        // прыгает назад, а лишь пересчитывает оставшееся.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing archive', index: 2, count: 2);
        await deliverArchive(archivePath, destination, params.name, op, progress);
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Записи архива — потоком, по мере обхода дерева.
  ///
  /// Потоком, а не списком: содержимое каждой записи читается прямо из своего
  /// провайдера в тот момент, когда её пишут. Ни временных копий, ни памяти под
  /// файл — tar пишется подряд, и держать в руках нечего.
  Stream<TarItem> _itemsOf(
    List<FsNode> sources,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required bool followLinks,
  }) async* {
    for (final source in sources) {
      await op.checkpoint();
      progress.startSource(source.name);
      yield* _itemsOfNode(source, source.name, op, progress, followLinks: followLinks);
    }
  }

  Stream<TarItem> _itemsOfNode(
    FsNode node,
    String entryName,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required bool followLinks,
  }) async* {
    await op.checkpoint();

    // Ссылка разбирается до того, как узел сочтут файлом: ссылка на каталог
    // файлом не является, и поток по ней не открыть.
    if (node is LinkNode && !followLinks) {
      // Ссылкой — то, ради чего мир Unix и пользуется tar.
      yield TarItem.link(name: entryName, linkTarget: node.reference, modified: node.modified);
      progress.advance();
      return;
    }

    final resolved = node is LinkNode ? await node.resolve().run(node) ?? node : node;

    if (resolved is DirectoryNode) {
      yield TarItem.directory(name: '$entryName/', mode: _modeOf(resolved, 0x1ed), modified: resolved.modified);
      progress.advance();

      final children = await resolved.provider.listChildren(resolved);
      for (final child in children) {
        if (child is ParentDirNode) {
          continue;
        }
        yield* _itemsOfNode(child, '$entryName/${child.name}', op, progress, followLinks: followLinks);
      }
      return;
    }

    final provider = resolved.provider;
    if (provider is! FileContentProvider) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }

    // Размер объявляется в заголовке **до** содержимого, поэтому он обязан
    // быть известен заранее. Источник, который его не знает (бывает у чужих
    // серверов), пришлось бы сперва вычитать целиком — а это отдельная цена, и
    // платить её молча неправильно.
    if (resolved.size < 0) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }

    yield TarItem.file(
      name: entryName,
      size: resolved.size,
      mode: _modeOf(resolved, 0x1a4),
      modified: resolved is FileNode ? resolved.modified : null,
      content: await (provider as FileContentProvider).openRead(resolved),
    );
    progress.advance();
  }

  /// Права из источника; их нет — обычные для файла или каталога.
  static int _modeOf(FsNode node, int fallback) {
    final mode = node is FileNode ? node.attributes.mode : 0;
    return mode == 0 ? fallback : mode;
  }

  /// Первое звено пути записи — тот источник, из которого она пришла.
  static String _sourceOf(String entryName) {
    final slash = entryName.indexOf('/');
    return slash < 0 ? entryName : entryName.substring(0, slash);
  }

  /// Считает объекты и байты — рядом с работой, а не перед ней.
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

  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String defaultNameOf(CommandContext context) {
    final sources = _sourcesOf(context);
    if (sources.length == 1) {
      return '${sources.single.name}${TarFormat.gzip.extension}';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name${TarFormat.gzip.extension}';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target?.directory?.pathString ?? '';
}

/// Что упаковать, куда и в каком виде.
class TarPackParams {
  const TarPackParams(
    this.sources,
    this.destination,
    this.name, {
    this.format = TarFormat.gzip,
    this.followLinks = false,
  });

  final List<FsNode> sources;
  final DirectoryNode destination;
  final String name;
  final TarFormat format;
  final bool followLinks;
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

  /// Ссылки: по умолчанию ложатся в архив ссылками — tar это умеет.
  bool followLinks = false;

  TarFormat format = TarFormat.gzip;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setFormat(TarFormat value) {
    // Имя идёт за форматом: выбрал `.tar` — расширение в поле меняется тут же,
    // иначе человек получил бы `.tar.gz` с несжатым содержимым.
    name = CreateTarArchiveCommand.withExtension(name, value);
    format = value;
    notifyListeners();
  }
}

/// Форма создания архива: имя, формат и ссылки.
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
    // Поле идёт за выбором формата: имя меняет не человек, а переключатель.
    if (_name.text != run.name) {
      _name.value = TextEditingValue(text: run.name, selection: TextSelection.collapsed(offset: run.name.length));
    }

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
            hintText: 'archive.tar.gz',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField(
          label: 'Format',
          child: FcRadioGroup<TarFormat>(
            direction: Axis.horizontal,
            options: {for (final value in TarFormat.values) value: value.title},
            value: run.format,
            onChanged: run.setFormat,
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        ),
      ],
    );
  }
}
