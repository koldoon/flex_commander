import 'app_build.dart';
import 'release.dart';

/// Чем кончилась проверка обновлений.
///
/// Перечислением случаев, а не «нашлось или нет»: отказов несколько, и каждый
/// человеку говорят по-своему — «у вас и так свежее», «сборки под ваш
/// процессор нет», «подменить себя приложение не может»
/// (`docs/spec/self-update.md`, §4).
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// Свежее некуда: выпуск не новее того, что запущено.
class AlreadyLatest extends UpdateCheckResult {
  const AlreadyLatest(this.version);

  /// Версия, которая стоит сейчас.
  final AppVersionRef version;
}

/// Есть что поставить.
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release, this.asset);

  final ReleaseInfo release;

  /// Файл под нашу архитектуру — тот, который качать.
  final ReleaseAsset asset;
}

/// Обновиться нельзя, и вот почему.
class UpdateImpossible extends UpdateCheckResult {
  const UpdateImpossible(this.reason);

  final UpdateObstacle reason;
}

/// Что помешало.
enum UpdateObstacle {
  /// Приложение не знает своей версии — сравнивать не с чем.
  unknownVersion,

  /// Выпусков нет вовсе.
  noReleases,

  /// Сборки под этот процессор в выпуске нет.
  noAssetForArchitecture,

  /// Сумма файла не названа: ставить непроверяемое нельзя.
  noChecksum,

  /// Подменить себя приложение не может: том только для чтения или чужие
  /// права.
  cannotReplaceItself,
}

/// Версия строкой — то, что показывают человеку.
typedef AppVersionRef = String;

/// Решает, стоит ли обновляться, и ничего для этого не делает.
///
/// Ни сети, ни файлов: источник выпусков и сведения о сборке приходят
/// интерфейсами, поэтому проверку целиком видно в одном месте — и она целиком
/// же проверяется.
class UpdateCheck {
  const UpdateCheck({required this.build, required this.source});

  final AppBuild build;
  final ReleaseSource source;

  Future<UpdateCheckResult> run() async {
    final mine = build.version;
    if (mine == null) {
      return const UpdateImpossible(UpdateObstacle.unknownVersion);
    }

    final release = await source.latest();
    if (release == null) {
      return const UpdateImpossible(UpdateObstacle.noReleases);
    }

    // Не новее — и разговор окончен: ни архитектура, ни права тут уже ни при
    // чём, а сказать надо ровно одно — «у вас и так свежее».
    if (release.version.compareTo(mine) <= 0) {
      return AlreadyLatest(mine.toString());
    }

    final asset = release.assetFor(build.architecture);
    if (asset == null) {
      return const UpdateImpossible(UpdateObstacle.noAssetForArchitecture);
    }
    if (asset.sha256.isEmpty) {
      return const UpdateImpossible(UpdateObstacle.noChecksum);
    }
    // Последней — самая дорогая для человека новость: место, куда ставить,
    // недоступно. Спрашиваем до загрузки, а не после.
    if (!build.canReplaceItself) {
      return const UpdateImpossible(UpdateObstacle.cannotReplaceItself);
    }

    return UpdateAvailable(release, asset);
  }
}
