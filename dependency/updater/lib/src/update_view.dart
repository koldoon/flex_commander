import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'release.dart';
import 'update_service.dart';

/// Окно «новая версия готова»: заметки выпуска и два ответа.
///
/// Показывается **после** загрузки, а не до: пока качается, человеку решать
/// нечего, и спрашивать его не о чем (`docs/spec/self-update.md`, §9).
void showUpdateReady(Application app, UpdateService updates, ReleaseInfo release, File archive) {
  final view = app.view;
  late final String dialogId;
  void close() => view.closeDialog(dialogId);

  dialogId = view.showDialog(
    DialogSpec(
      // Версия прямо в заголовке: это первое, что хотят знать.
      title: app.strings.tr('Version {version} is ready', args: {'version': '${release.version}'}),
      id: 'app.update',
      resizable: true,
      takesFocus: true,
      content: UpdateReadyView(
        notes: release.notes,
        onLater: () {
          // «Позже» — до следующего запуска, а не навсегда: забыть о выпуске
          // совсем это выключить проверку, и для этого есть флажок.
          updates.postpone(release);
          close();
        },
        onRestart: () {
          close();
          unawaited(_restart(app, updates, archive));
        },
      ),
      onDismiss: () {
        updates.postpone(release);
        close();
      },
    ),
  );
}

/// Передать дело помощнику и закрыться.
///
/// Закрываемся **сами**: помощник ждёт нашего выхода, потому что занятый
/// каталог `.app` не подменить.
Future<void> _restart(Application app, UpdateService updates, File archive) async {
  try {
    await updates.install(archive);
  } on FsError catch (failure) {
    // С причиной, а не общей фразой: «не вышло поставить» не говорит ничего —
    // ни где искать, ни что делать. Одно такое сообщение уже стоило живого
    // разбирательства (`docs/spec/self-update.md`, §12).
    app.toasts.fail('${app.strings.tr('Could not install the update')}: ${app.strings.describe(failure)}');
    return;
  } on Object catch (error) {
    app.toasts.fail('${app.strings.tr('Could not install the update')}: $error');
    return;
  }
  // Просим систему завершить приложение обычным путём: только так сработает
  // `onExitRequested`, в котором дописываются настройки (`lib/app.dart`).
  await ServicesBinding.instance.exitApplication(ui.AppExitType.cancelable);
}

/// Содержимое окна: заметки выпуска и ряд кнопок.
class UpdateReadyView extends StatelessWidget {
  const UpdateReadyView({
    super.key,
    required this.notes,
    required this.onLater,
    required this.onRestart,
    this.openLink = openWithSystem,
  });

  /// Заметки выпуска — как их написали в релизе, без разбора разметки.
  final String notes;

  final VoidCallback onLater;
  final VoidCallback onRestart;

  /// Чем открыть ссылку из заметок.
  ///
  /// Системой, а не внутри окна: в заметках стоит «Full Changelog» на GitHub, и
  /// читать его человек пойдёт в браузер — показывать страницу в окне
  /// обновления нечем и незачем.
  final Future<void> Function(String url) openLink;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return SizedBox(
      // Доля экрана: заметки бывают в десять строк и в сорок, а окно от этого
      // прыгать шириной не должно.
      width: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
      child: FcDialogBody(
        // Прокручивает разметка, а не тело окна: у растянутого окна тело
        // отдаёт содержимому высоту целиком и своей прокрутки не ставит, а
        // заметки бывают длиннее любого окна (`docs/spec/dialog-body.md`).
        scrolls: false,
        actions: [
          FcButton(label: context.strings.tr('Later'), onPressed: onLater),
          FcButton(label: context.strings.tr('Restart'), onPressed: onRestart, primary: true),
        ],
        child:
            notes.trim().isEmpty
                ? Text(context.strings.tr('No release notes'), style: theme.dialogTextStyle)
                : SingleChildScrollView(
                  child: MarkdownBody(
                    data: notes.trim(),
                    styleSheet: fcMarkdownStyle(theme),
                    // Врезки кода рисуем сами — ради подсветки, которой у них
                    // не было. Рисовальщиков диаграмм тут нет и не нужно:
                    // описание выпуска их не содержит.
                    builders: {'pre': FcFencedBlockBuilder(blocks: const [], maxWidth: double.infinity)},
                    onTapLink: (_, href, _) {
                      if (href != null && href.isNotEmpty) {
                        unawaited(openLink(href));
                      }
                    },
                  ),
                ),
      ),
    );
  }
}
