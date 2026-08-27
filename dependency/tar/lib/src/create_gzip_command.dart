import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'archive_output.dart';

/// Сжать один файл в `.gz`.
///
/// Отдельная команда, а не пункт в окне `Mk Tar`, и причина та же, по которой у
/// модуля два провайдера: **gzip — это сжатие одного потока, а не набор
/// файлов**. `dump.sql.gz` — это сжатый `dump.sql`, и ничего больше: имён
/// внутри нет, каталога внутри быть не может, и «упаковать три файла в один
/// `.gz`» — просьба, которую формат не выполняет.
///
/// Отсюда и условие выполнимости: ровно один объект, и он не каталог. Каталог
/// и несколько объектов — это `Mk Tar`, и она рядом.
///
/// Клавиши нет, как и у `Mk Tar`: свободных в ряду не осталось, а место
/// команды без клавиши — палитра.
class CreateGzipCommand extends AppCommand {
  CreateGzipCommand({required StagingArea staging}) : _staging = staging;

  static const String commandId = 'gz.create';

  /// Имя будущего файла.
  static const String nameParam = 'name';

  final StagingArea _staging;

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Gz';

  @override
  String get description => 'Compress a single file into a new gz file';

  @override
  Set<String> get keywords => const {'gzip', 'compress', 'archive'};

  String get dialogTitle => 'Compress into gz';

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy) {
      return false;
    }

    // Ровно один, и не каталог: сжимается **поток**, а не набор файлов.
    // Ссылка сюда проходит — куда она ведёт, выяснится при работе, и вести она
    // может как раз в файл.
    final sources = _sourcesOf(context);
    if (sources.length != 1 || sources.single is DirectoryNode) {
      return false;
    }

    final destination = context.target.directory;
    return destination != null && destination.provider.canReceive;
  }

  List<FsNode> _sourcesOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute(CommandContext context) async {
    final sources = _sourcesOf(context);
    final destination = context.target.directory;
    if (sources.length != 1 || destination == null) {
      return;
    }
    final source = sources.single;

    Future<void> compress(String typed, [FcAsyncRun? run]) async {
      final name = typed.trim();
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      final provider = destination.provider;
      if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
        // Молча затирать существующий файл нельзя: имя правится тут же в окне.
        throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
      }

      // Аренда обоих концов: работу можно убрать в фон, и любая из панелей за
      // это время вправе уйти из своего архива.
      final from = context.panel.leaseProvider();
      final into = context.target.leaseProvider();

      try {
        final operation = packOperation();
        final params = GzipPackParams(source, destination, name);
        if (run != null) {
          await run.run(operation, params, message: 'Compressing…');
        } else {
          await operation.run(params);
        }
      } finally {
        await from?.release();
        await into?.release();
      }

      await context.target.reload();
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await compress(given);
      return;
    }

    final view = context.app.view;
    late final _CompressRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: dialogTitle,
          takesFocus: true,
          content: FcAsyncRunDialog(run: run, form: (_) => _CompressForm(run: run)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = _CompressRun(
      app: context.app,
      commandId: id,
      title: dialogTitle,
      failureMessage: '$label failed',
      show: present,
      name: defaultNameOf(source),
      destinationPath: destination.pathString,
    );
    run.onStart = () => compress(run.name, run);

    present();
  }

  /// Имя по умолчанию: имя файла плюс `.gz`, как это делает сам `gzip`.
  ///
  /// Расширение исходного файла остаётся на месте — по нему потом и понятно,
  /// что внутри: `dump.sql.gz` разжимается в `dump.sql`, и провайдер `gz`
  /// показывает ровно это имя.
  @visibleForTesting
  static String defaultNameOf(FsNode source) => '${source.name}.gz';

  /// Сжатие: поток источника через gzip во временный файл и оттуда приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник, по той же причине, что и у
  /// tar: сколько байт получится, до конца работы неизвестно, а приёмник вправе
  /// знать размер заранее.
  @visibleForTesting
  Operation<GzipPackParams, void> packOperation() {
    return TaskOperation<GzipPackParams, void>((op, params) async {
      final destination = params.destination;
      final progress = TransferProgress(op);
      progress.beginStage('compressing', index: 1, count: 2);

      final source = await _fileOf(params.source);
      final provider = source.provider;
      if (provider is! FileContentProvider) {
        throw FsError(source.pathString, FsErrorKind.notSupported);
      }

      // Объект здесь ровно один, и считать нечего: размер известен сразу.
      // Неизвестен он бывает у файла на сервере, который о нём не сказал, — и
      // тогда полоса идёт по байтам, а доли не показывает.
      progress.countOne(source.size);
      progress.countingFinished();

      final staged = await _staging.open('flex_commander_gz_create');
      final archivePath = p.join(staged.path, params.name);

      try {
        progress.startSource(source.name);
        final item = progress.startItem(source.name, bytes: source.size);

        final bytes = (await (provider as FileContentProvider).openRead(source)).asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        });

        final sink = File(archivePath).openWrite();
        try {
          await sink.addStream(gzip.encoder.bind(bytes));
        } finally {
          await sink.close();
        }
        progress.finishItem(item);

        await op.checkpoint();

        // Второе плечо: сжатые байты уходят приёмнику. Их количество до этого
        // момента неизвестно, поэтому работа прирастает здесь.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing file', index: 2, count: 2);
        await deliverArchive(archivePath, destination, params.name, op, progress);
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Файл, который сжимаем: ссылку разбираем, каталог отвергаем.
  ///
  /// Каталог сюда доходит только вызовом со значением, мимо окна: команда без
  /// параметра его не предлагает вовсе. Но соврать всё равно нельзя — каталог в
  /// `.gz` не кладётся ни при каком способе вызова.
  static Future<FsNode> _fileOf(FsNode source) async {
    final resolved = source is LinkNode ? await source.resolve().run(source) ?? source : source;
    if (resolved is DirectoryNode) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }
    return resolved;
  }
}

/// Что сжать, куда и под каким именем.
class GzipPackParams {
  const GzipPackParams(this.source, this.destination, this.name);

  final FsNode source;
  final DirectoryNode destination;
  final String name;
}

/// Прогон сжатия вместе с тем, что спрашивают до его начала.
class _CompressRun extends FcAsyncRun {
  _CompressRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.name,
    required this.destinationPath,
  });

  String name;

  /// Куда ляжет файл. Не редактируется — приёмник задан панелью.
  final String destinationPath;
}

/// Форма: куда и под каким именем.
///
/// Выбирать здесь нечего — ни формата, ни ссылок: сжимается один поток одним
/// способом. Окно всё же есть, потому что имя правится и приёмник видно.
class _CompressForm extends StatefulWidget {
  const _CompressForm({required this.run});

  final _CompressRun run;

  @override
  State<_CompressForm> createState() => _CompressFormState();
}

class _CompressFormState extends State<_CompressForm> {
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
          label: 'File name',
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: 'dump.sql.gz',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
      ],
    );
  }
}
