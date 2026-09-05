import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'file_icon_service.dart';
import 'file_icon_settings.dart';

/// Иконка строки по правилам: глиф, картинка с диска или значок системы.
///
/// Приносит одну службу — [FileIcons]. Выключишь модуль, и панель рисует
/// иконки сама, теми же глифами, что и всегда: правила — это надстройка, а не
/// замена (`docs/spec/file-icons.md`).
///
/// Две службы, на которые он опирается, тоже необязательны. Нет модуля типов —
/// правила по содержимому не совпадают; нет значков системы (а их приносит
/// платформенный модуль приложения) — не совпадают правила с `system`. Ни в
/// том, ни в другом случае ничего не ломается: срабатывает следующее правило.
class FileIconRules implements FcFrontendModule {
  const FileIconRules();

  @override
  String get id => 'fc.icons';

  @override
  String get title => 'File icons';

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;
    FileIconSettings settingsOf() => settings.section(FileIconSettings.new);

    registry.service<FileIcons>(
      (services) => FileIconService(
        settings: settingsOf,
        contentTypes: _optional<ContentTypes>(services),
        systemIcons: _optional<SystemIcons>(services),
      ),
    );

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'size',
          min: 0,
          max: FileIconSettings.maxSize,
          defaultValue: 0,
          title: 'Icon size',
          description: 'Row icon size in points; 0 keeps the size the theme sets',
          note: 'Rows get taller to fit',
          read: () => settingsOf().size,
          write: (value) => settingsOf().size = value,
        ),
        SettingsField.flag(
          'system',
          defaultValue: false,
          title: 'System icons',
          description: 'Show the icon the system knows for files and folders on disk',
          read: () => settingsOf().system,
          write: (value) => settingsOf().system = value,
        ),
      ], save: settings.save),
    );
  }

  /// Служба, которой может не быть вовсе.
  ///
  /// `resolveAll` вместо `resolve`: тот бросает, если реализации нет, а здесь
  /// её отсутствие — обычное дело, а не ошибка сборки.
  static T? _optional<T>(FcServices services) {
    final found = services.resolveAll<T>();
    return found.isEmpty ? null : found.first;
  }
}
