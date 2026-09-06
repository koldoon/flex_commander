import 'package:fc_api/fc_api.dart';
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
    registry.strings('ru', {
      'Files read at once': 'Файлов читается разом',
      'How many files are read in parallel to tell what they are':
          'Сколько файлов читается одновременно, чтобы понять их тип',
      'Content types': 'Типы содержимого',
    });

    final settings = registry.settings;
    ContentTypesSettings settingsOf() => settings.section(ContentTypesSettings.new);

    registry.service<ContentTypes>((services) => ContentTypeService(concurrency: () => settingsOf().concurrency));

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.integer(
          'concurrency',
          min: 1,
          max: 16,
          defaultValue: ContentTypesSettings.defaultConcurrency,
          title: strings.tr('Files read at once'),
          description: strings.tr('How many files are read in parallel to tell what they are'),
          read: () => settingsOf().concurrency,
          write: (value) => settingsOf().concurrency = value,
        ),
      ], save: settings.save);
    });
  }
}
