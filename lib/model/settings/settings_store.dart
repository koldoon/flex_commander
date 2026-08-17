import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/serialization.dart';
import 'app_settings.dart';

/// Чтение и запись настроек приложения.
///
/// Файл лежит в домашнем каталоге пользователя (`~/.flex-commander/settings.json`),
/// как и в референсной реализации: его удобно править руками, и он одинаково
/// работает на всех платформах.
class SettingsStore {
  SettingsStore({required this.filePath, this.fallbackPath = '', this.onError});

  /// Хранилище в стандартном месте.
  factory SettingsStore.forHome(String homePath, {void Function(Object error)? onError}) =>
      SettingsStore(filePath: p.join(homePath, directoryName, fileName), fallbackPath: homePath, onError: onError);

  static const String directoryName = '.flex-commander';
  static const String fileName = 'settings.json';

  final String filePath;

  /// Каталог, который подставляется панелям, если в файле пути нет.
  final String fallbackPath;

  /// Куда сообщать о проблемах. Настройки — не то, из-за чего стоит падать:
  /// приложение должно запускаться и с испорченным файлом.
  final void Function(Object error)? onError;

  /// Читает настройки. Любая ошибка чтения или разбора даёт умолчания.
  Future<AppSettings> load() async {
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        return AppSettings.defaults(fallbackPath);
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return AppSettings.defaults(fallbackPath);
      }

      // Разбор дописывает в готовые умолчания то, что нашлось в файле: чего
      // в нём нет, остаётся умолчанием само, без проверок в каждом поле.
      final settings = AppSettings.defaults(fallbackPath);
      extract(settings, jsonDecode(content));
      return settings;
    } catch (error) {
      onError?.call(error);
      return AppSettings.defaults(fallbackPath);
    }
  }

  /// Пишет настройки атомарно: сначала во временный файл рядом, потом
  /// переименование. Прерванная запись не оставляет обрезанный settings.json.
  Future<void> save(AppSettings settings) async {
    final file = File(filePath);
    final temp = File('$filePath.tmp');
    try {
      await file.parent.create(recursive: true);
      final json = const JsonEncoder.withIndent('  ').convert(serialize(settings));
      await temp.writeAsString('$json\n', flush: true);
      await temp.rename(filePath);
    } catch (error) {
      onError?.call(error);
      try {
        if (await temp.exists()) {
          await temp.delete();
        }
      } catch (_) {
        // Уборка мусора не должна порождать вторую ошибку.
      }
    }
  }
}
