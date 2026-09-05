import 'package:fc_ui_api/fc_ui_api.dart';

import 'content_type_service.dart';
import 'content_types_settings.dart';

/// Тип файла по его содержимому.
///
/// Приносит одну службу — [ContentTypes] — и ничего больше: ни колонки, ни
/// команды. Колонка `content.type` появится с реестром колонок (Б2), а первым
/// службу спрашивают иконки (`docs/spec/file-icons.md`).
///
/// Выключишь модуль — никто ничего не читает, и показ обходится тем, что знает
/// по имени. Ровно как без перетаскивания.
class ContentTypeDetection implements FcFrontendModule {
  const ContentTypeDetection();

  @override
  String get id => 'fc.contentTypes';

  @override
  String get title => 'Content types';

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;
    ContentTypesSettings settingsOf() => settings.section(ContentTypesSettings.new);

    registry.service<ContentTypes>((services) => ContentTypeService(concurrency: () => settingsOf().concurrency));

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'concurrency',
          min: 1,
          max: 16,
          defaultValue: ContentTypesSettings.defaultConcurrency,
          title: 'Files read at once',
          description: 'How many files are read in parallel to tell what they are',
          read: () => settingsOf().concurrency,
          write: (value) => settingsOf().concurrency = value,
        ),
      ], save: settings.save),
    );
  }
}
