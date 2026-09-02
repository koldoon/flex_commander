import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'gzip_pack.dart';

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
  CreateGzipCommand();

  static const String commandId = 'gz.create';

  /// Имя будущего файла.
  static const String nameParam = 'name';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Gz';

  @override
  String get description => 'Compress a single file into a new gz file';

  @override
  Set<String> get keywords => const {'gzip', 'compress', 'archive', 'pack'};

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
    if (sources.length != 1 || sources.single.isDirectory) {
      return false;
    }

    // Занятый приёмник принять ничего не может: он сам сейчас читает.
    final target = context.target;
    return target != null && !target.busy && target.path.isNotEmpty && target.source.canReceive;
  }

  /// Что сжимать: помеченное, а без пометки — то, что под курсором.
  List<FileEntry> _sourcesOf(CommandContext context) => [
    for (final entry in context.targets)
      if (!entry.isParent) entry,
  ];

  @override
  Future<void> execute(CommandContext context) async {
    final sources = _sourcesOf(context);
    final target = context.target;
    if (sources.length != 1 || target == null) {
      return;
    }

    Future<void> compress(String typed, [FcAsyncRun? run]) async {
      final name = typed.trim();
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      // Аренда обоих концов и проверка занятого имени — дело ядра.
      final spec = OperationSpec(
        kind: GzipPacking.kind,
        targets: Targets.current(context.panel.id),
        destination: target.id,
        options: {GzipPacking.nameOption: name},
      );

      final operation = context.app.runOperation();
      if (run != null) {
        await run.run(operation, spec, message: 'Compressing…');
      } else {
        await operation.run(spec);
      }

      await target.reload();
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
      name: defaultNameOf(sources.single),
      destinationPath: target.path,
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
  static String defaultNameOf(FileEntry source) => '${source.name}.gz';
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
