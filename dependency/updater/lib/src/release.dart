import 'app_version.dart';

/// Выпуск, лежащий на GitHub.
///
/// Значение: чем он приехал — сетью или подставкой в проверке — решению об
/// обновлении всё равно.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.tag, this.notes = '', this.assets = const []});

  final AppVersion version;

  /// Тег, которым выпуск назван: `v0.0.72`. Показывать его человеку не нужно —
  /// он видит [version], — но в имени файла стоит именно тег.
  final String tag;

  /// Заметки выпуска — то, что покажут в окне.
  final String notes;

  final List<ReleaseAsset> assets;

  /// Сборка под эту архитектуру; null — такой нет.
  ///
  /// По имени файла, а не по порядку: ассетов у выпуска бывает несколько, и
  /// взять первый попавшийся значило бы однажды подменить рабочее приложение
  /// сборкой под чужой процессор (`docs/spec/self-update.md`, §4).
  ReleaseAsset? assetFor(String architecture) {
    for (final asset in assets) {
      if (asset.name.contains('macos-$architecture')) {
        return asset;
      }
    }
    return null;
  }

  @override
  String toString() => 'ReleaseInfo($tag, ${assets.length} asset(s))';
}

/// Файл выпуска: что качать и с чем сверять.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.sha256 = '', this.size = 0});

  final String name;
  final String url;

  /// Сумма, которую назвал GitHub (поле `digest`, без приставки `sha256:`).
  ///
  /// Пусто — сервер её не назвал; такой файл не ставится вовсе. Своя подпись
  /// нам не нужна ровно потому, что эта сумма приезжает по `https` вместе со
  /// ссылкой (`docs/spec/self-update.md`, §3).
  final String sha256;

  /// Размер в байтах — чтобы показать ход загрузки.
  final int size;

  @override
  String toString() => 'ReleaseAsset($name, $size байт)';
}

/// Откуда приложение узнаёт о выпусках.
///
/// Интерфейсом, а не прямым запросом: проверки не ходят в сеть, а решение об
/// обновлении не должно знать ни про GitHub, ни про JSON.
abstract interface class ReleaseSource {
  /// Последний выпуск; null — выпусков нет вовсе.
  ///
  /// Неудача — это исключение `FsError`, а не null: «выпусков нет» и «не
  /// дозвонились» — разные ответы, и путать их нельзя.
  Future<ReleaseInfo?> latest();
}
