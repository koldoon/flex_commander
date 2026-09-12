import 'dart:io';

import 'package:fc_core_api/fc_core_api.dart';

import 'app_build.dart';
import 'release.dart';
import 'update_check.dart';
import 'update_download.dart';
import 'update_install.dart';
import 'updater_settings.dart';

/// Обновление приложения целиком: спросить, скачать, подменить.
///
/// Собирает вместе то, что по отдельности уже проверено: решение
/// ([UpdateCheck]), загрузку ([UpdateDownload]) и подмену ([UpdateInstall]).
/// Своего показа не знает — что говорить человеку, решает тот, кто позвал
/// (`docs/spec/self-update.md`, §9).
class UpdateService {
  UpdateService({
    required this.build,
    required this.source,
    required this.processes,
    required this.settings,
    required this.save,
    required Directory cache,
    DateTime Function()? now,
  }) : _cache = cache,
       _now = now ?? DateTime.now;

  final AppBuild build;
  final ReleaseSource source;

  /// Чем запускать программы — **способом узнать**, а не значением: распаковка
  /// и подмена нужны на последнем шаге, а проверка и загрузка обходятся без
  /// них вовсе. Приложение, собранное без модуля платформы, от этого не
  /// падает на проверке обновлений.
  final ProcessRunner Function() processes;
  final UpdaterSettings Function() settings;

  /// Попросить записать настройки — после проверки меняется её дата.
  final void Function() save;

  final Directory _cache;
  final DateTime Function() _now;

  /// Спросить GitHub. [byHand] — проверку попросил человек.
  ///
  /// У проверки по расписанию два отличия: она молчит о том, что всё свежее, и
  /// пропускает отложенный выпуск. Человек, нажавший «Check now», ответ
  /// получает всегда — нажатие без ответа это ошибка.
  Future<UpdateCheckResult> check({bool byHand = false}) async {
    final memory = settings();
    if (!byHand && !memory.dueAt(_now())) {
      return AlreadyLatest(build.version?.toString() ?? '');
    }

    final result = await UpdateCheck(build: build, source: source).run();

    // Дату ставим и при неудаче: иначе недоступный сервер спрашивался бы на
    // каждом запуске, а ответ от этого не изменится.
    memory.lastCheck = _now().toIso8601String();
    save();

    if (!byHand && result is UpdateAvailable && memory.postponed == result.release.tag) {
      return AlreadyLatest(build.version?.toString() ?? '');
    }
    return result;
  }

  /// Скачать выпуск. Ход — в [onProgress], отмена — в [canceled].
  Future<File> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    bool Function()? canceled,
  }) => UpdateDownload(into: _cache).fetch(asset, onProgress: onProgress, canceled: canceled);

  /// Распаковать скачанное и передать дело помощнику.
  ///
  /// Возвращается сразу: дальше приложение обязано закрыться — помощник ждёт
  /// именно этого.
  Future<void> install(File archive) async {
    final installer = UpdateInstall(processes: processes(), workspace: _cache);
    final replacement = await installer.unpack(archive);
    await installer.handOver(replacement: replacement, target: build.bundlePath, pid: pid);
  }

  /// Отложить выпуск до следующего запуска.
  void postpone(ReleaseInfo release) {
    settings().postponed = release.tag;
    save();
  }

  /// Убрать отложенную сборку: раз мы запустились, возвращаться не к чему.
  Future<void> forgetPreviousBuild() async {
    if (build.bundlePath.isEmpty) {
      return;
    }
    await UpdateInstall.forgetBackup(build.bundlePath);
  }
}
