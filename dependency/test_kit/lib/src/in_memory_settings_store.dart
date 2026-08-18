import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/settings/settings_store.dart';

/// Настройки в памяти вместо файла на диске.
///
/// Не только ради скорости: виджет-тесты идут в поддельном времени, и
/// настоящее обращение к диску в них не завершается никогда — приложение,
/// собранное с обычным хранилищем, просто повисает на чтении настроек.
///
/// Тем, кто проверяет само сохранение, нужен настоящий [SettingsStore] с
/// временным файлом: у них и время настоящее.
class InMemorySettingsStore extends SettingsStore {
  InMemorySettingsStore({AppSettings? settings, String homePath = '/home'})
    : _settings = settings,
      super(filePath: '', fallbackPath: homePath);

  AppSettings? _settings;

  /// Что лежит в хранилище сейчас.
  AppSettings? get saved => _settings;

  @override
  Future<AppSettings> load() async => _settings ?? AppSettings.defaults(fallbackPath);

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}
