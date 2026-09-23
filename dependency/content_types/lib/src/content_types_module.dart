import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'content_type_cell.dart';
import 'content_type_service.dart';
import 'content_types_settings.dart';

/// Тип файла по его содержимому.
///
/// Приносит службу [ContentTypes] и колонку «Type», которая её показывает.
/// Первыми службу спрашивают иконки (`docs/spec/file-icons.md`).
///
/// Выключишь модуль — никто ничего не читает, и показ обходится тем, что знает
/// по имени. Ровно как без перетаскивания.
class ContentTypeDetection implements FcFrontendModule, FcBackendModule {
  const ContentTypeDetection();

  @override
  String get id => 'fc.contentTypes';

  @override
  String get title => 'Content types';

  /// Колонка «Type»: что за файл — по первым байтам.
  ///
  /// **Без сортировки.** Сравнение живёт в ядре и работает над узлами, а тип —
  /// знание экранное: ядру он неизвестен, и обещать сортировку, которой не
  /// будет, нельзя (`docs/spec/content-types.md`, §2а).
  ///
  /// **По умолчанию невидима**: показать её значит прочитать по четыре
  /// килобайта с каждого видимого файла, а на `ssh` и в архиве это поход по
  /// сети за каждым. Такое включают, зная, чего просят.
  static const ColumnSpec column = ColumnSpec(
    id: 'content.type',
    title: 'Type',
    width: 104,
    visible: false,
    sortable: false,
  );

  /// Ядровая половина — одно объявление и ничего больше.
  ///
  /// Паспорт колонки объявляется по разу на каждой стороне, одной и той же
  /// константой: иначе геометрии есть где разъехаться, а сверка двух сторон
  /// (`column-registry.md`, §3.2) на то и заведена. Сравнения нет — колонка
  /// несортируемая, ровно как значок.
  @override
  void installBackend(BackendRegistry registry) {
    registry.column(column);
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {
      'Files read at once': 'Файлов читается разом',
      'How many files are read in parallel to tell what they are':
          'Сколько файлов читается одновременно, чтобы понять их тип',
      'Content types': 'Типы содержимого',
      'Type': 'Тип',
    });

    final settings = registry.settings;
    ContentTypesSettings settingsOf() => settings.section(ContentTypesSettings.new);

    registry.service<ContentTypes>((services) => ContentTypeService(concurrency: () => settingsOf().concurrency));

    // Служба спрашивается **в ячейке**, а не здесь: объявление собирается один
    // раз при установке модуля, а служба к тому времени ещё не заведена.
    registry.column(
      column,
      build:
          (context, cell) => ContentTypeCell(
            entry: cell.entry,
            selected: cell.selected,
            contentOf: cell.contentOf,
            types: registry.services.resolve<ContentTypes>(),
          ),
    );

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
