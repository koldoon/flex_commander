import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'release.dart';
import 'update_check.dart';
import 'update_service.dart';
import 'update_view.dart';

/// Проверить, нет ли сборки новее, и поставить её.
///
/// Одна команда на оба случая — палитру и кнопку в настройках: дело у них одно
/// (`docs/spec/self-update.md`, §9).
class CheckForUpdatesCommand extends AppCommand {
  CheckForUpdatesCommand({required this.updates});

  static const String commandId = 'app.checkForUpdates';

  final UpdateService Function() updates;

  @override
  String get id => commandId;

  @override
  String get label => tr('Check for updates');

  @override
  String get description => tr('Ask GitHub whether a newer build is out');

  @override
  Set<String> get keywords => const {'upgrade', 'new version', 'release', 'download'};

  /// Спросить можно всегда: сеть может не ответить, но это уже ответ.
  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) => runUpdate(context.app, updates(), byHand: true);
}

/// Проверка при запуске — раз в сутки и молча.
///
/// Отдельной командой, а не флагом у первой: стартовые команды приложение
/// заводит само, и различие «спросил человек» решается здесь, а не внутри.
class CheckForUpdatesAtStartupCommand extends AppCommand {
  CheckForUpdatesAtStartupCommand({required this.updates});

  static const String commandId = 'app.checkForUpdates.startup';

  final UpdateService Function() updates;

  @override
  String get id => commandId;

  @override
  String get label => tr('Check for updates at startup');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final service = updates();
    // Отложенная сборка рядом больше не нужна: раз мы поднялись, возвращаться
    // не к чему (`docs/spec/self-update.md`, §6).
    await service.forgetPreviousBuild();

    // Немного погодя: запуск — это чтение каталогов и первый кадр, и отнимать
    // у них время ради сети незачем.
    Timer(const Duration(seconds: 5), () => unawaited(runUpdate(context.app, service, byHand: false)));
  }
}

/// Проверить и, если есть что, скачать и предложить перезапуск.
///
/// [byHand] — проверку попросил человек: тогда ответ он получает всегда, а
/// молчание было бы нажатием без ответа.
Future<void> runUpdate(Application app, UpdateService updates, {required bool byHand}) async {
  final strings = app.strings;

  final UpdateCheckResult result;
  try {
    result = await updates.check(byHand: byHand);
  } on FsError catch (failure) {
    if (byHand) {
      app.toasts.fail(strings.describe(failure));
    }
    return;
  }

  switch (result) {
    case AlreadyLatest():
      if (byHand) {
        app.toasts.show(strings.tr('You are up to date'));
      }
    case UpdateImpossible(:final reason):
      if (byHand) {
        app.toasts.fail(_explain(strings, reason));
      }
    case UpdateAvailable(:final release, :final asset):
      await _fetchAndOffer(app, updates, release, asset);
  }
}

/// Качает выпуск фоновой работой и показывает окно, когда скачалось.
Future<void> _fetchAndOffer(Application app, UpdateService updates, ReleaseInfo release, ReleaseAsset asset) async {
  final strings = app.strings;
  final runId = 'update-${release.tag}';

  var canceled = false;
  final operation = TaskOperation<void, File>((op, _) async {
    return updates.download(
      asset,
      canceled: () => canceled || op.isCanceled,
      // В сообщении — объём, а не то же самое слово: полоска работы рисует
      // «название: сообщение», и одинаковый текст читался бы как «Загрузка
      // 0.0.73: Загрузка 0.0.73» (поймано живьём).
      onProgress:
          (received, total) => op.report(
            message: total > 0 ? '${formatBytesLong(received)} / ${formatBytesLong(total)}' : formatBytesLong(received),
            bytesTransferred: received,
            bytesTotal: total > 0 ? total : null,
          ),
    );
  });

  app.operations.register(
    OperationRun(
      runId: runId,
      operation: operation,
      title: strings.tr('Downloading {version}', args: {'version': '${release.version}'}),
    ),
  );
  // Сразу в фон: окна у этой работы нет, а полоска под панелью есть.
  app.operations.sendToBackground(runId, owner: ViewportPosition.left);

  try {
    operation.start(null);
    final archive = await operation.result;
    app.operations.forget(runId);
    showUpdateReady(app, updates, release, archive);
  } on OperationCanceled {
    canceled = true;
    app.operations.forget(runId);
  } on FsError catch (failure) {
    app.operations.forget(runId);
    app.toasts.fail(strings.describe(failure));
  }
}

/// Почему обновиться нельзя — словами, а не кодом отказа.
String _explain(Strings strings, UpdateObstacle reason) => switch (reason) {
  UpdateObstacle.unknownVersion => strings.tr('This build does not know its own version'),
  UpdateObstacle.noReleases => strings.tr('No releases published yet'),
  UpdateObstacle.noAssetForArchitecture => strings.tr('No build for this processor'),
  UpdateObstacle.noChecksum => strings.tr('The release has no checksum to verify'),
  UpdateObstacle.cannotReplaceItself => strings.tr('Cannot write to the application folder'),
};
