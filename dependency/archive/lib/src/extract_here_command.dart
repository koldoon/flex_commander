import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'archive_extract.dart';

/// Распаковать архив туда же, где он лежит.
///
/// Приёмника у заявки нет: место у каждого архива своё — тот каталог, где он
/// сам. Помеченные в разных ветвях дерева разъезжаются каждый к себе
/// (`docs/spec/archive-here.md`, §2).
class ExtractHereCommand extends AppCommand {
  static const String commandId = 'archive.extractHere';

  @override
  String get id => commandId;

  @override
  String get label => tr('Extract here');

  @override
  String get description => tr('Unpack the archive into the directory where it lies');

  @override
  Set<String> get keywords => const {'unzip', 'zip', '7z'};

  /// Раскрываемая строка — и есть архив: что именно открывается, знает не
  /// команда, а строка (`FileEntry.mountsAsBranch`, А19).
  static bool _isArchive(FileEntry entry) => entry.mountsAsBranch;

  /// Архивы среди целей — тем же правилом, что у всех файловых работ:
  /// помеченное, а без пометки строка под курсором.
  ///
  /// Только видимые строки: помеченное в других каталогах сюда не попадает, и
  /// это честно — проверка отвечает за то, будет ли от нажатия толк, а не
  /// перебирает дерево целиком.
  static List<FileEntry> archivesOf(Session panel) {
    final marked = [
      for (final entry in panel.entries)
        if (panel.isMarked(entry) && _isArchive(entry)) entry,
    ];
    if (marked.isNotEmpty || panel.markedPaths.isNotEmpty) {
      return marked;
    }
    final row = panel.currentEntry;
    return row != null && !row.isParent && _isArchive(row) ? [row] : const [];
  }

  /// Своего каталога у списка может не быть вовсе — находки, «Избранное»:
  /// «по месту» там ничего не значит, а молчаливого выбора «куда-нибудь» быть
  /// не должно (§2).
  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    return !panel.busy &&
        panel.source.contentKind == SourceInfo.files &&
        panel.source.canReceive &&
        archivesOf(panel).isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final archives = archivesOf(panel);
    if (archives.isEmpty) {
      return;
    }

    // Каталоги, куда ляжет содержимое: их же и перечитываем. Спрашиваются до
    // работы — после неё строк уже может не быть.
    final places = {for (final entry in archives) entry.directoryPath};

    final view = context.app.view;
    late final FcAsyncRun run;
    final title = archives.length == 1 ? '${tr('Extract')} «${archives.single.name}»' : titleOf(archives.length);

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: title,
          takesFocus: true,
          // Своего у окна ничего нет: ни имени спрашивать, ни места — оно
          // известно. Остаётся ход работы, её вопросы и разбор неудачи.
          content: FcAsyncRunDialog(run: run, form: (_) => const SizedBox.shrink()),
          onDismiss: run.dismiss,
        ),
      );
    }

    run = FcAsyncRun(
      app: context.app,
      commandId: id,
      title: title,
      failureMessage: '${tr('Extract here')} ${tr('failed')}',
      show: present,
    );

    present();
    try {
      await run.run(
        context.app.runOperation(),
        OperationSpec(kind: ArchiveExtraction.kind, targets: Targets.marked(panel.id, under: panel.currentRef)),
        message: tr('Extracting…'),
      );
    } finally {
      // Пометку снимает та работа, которая по ней и шла.
      panel.clearMarks(by: MarkChange.work);
      // Каталоги теперь показывают не то, что на диске: там появилось
      // распакованное.
      await reloadPanelsAt(context.app, places.toList());
    }
  }

  String titleOf(int count) => plural(count, one: 'Extract {n} archive', other: 'Extract {n} archives');
}
