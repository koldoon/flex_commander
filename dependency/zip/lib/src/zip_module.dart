import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'create_archive_command.dart';
import 'zip_pack.dart';
import 'zip_tree_provider.dart';

/// Zip-архив как дерево — и то, чем его упаковывают.
///
/// Один класс на обе стороны: половины у модуля разные, а модуль один — тот же
/// идентификатор, тот же раздел настроек, та же строка в справке. Что куда
/// объявляется, решает не класс, а реестр: окно из [installBackend] объявить
/// нечем, источник из [installFrontend] — тоже (`docs/modules.md`).
class ZipArchiver implements FcBackendModule, FcFrontendModule {
  const ZipArchiver();

  @override
  String get id => 'fc.zip_archiver';

  @override
  String get title => 'Zip archives';

  /// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
  /// которым файл открывается как каталог.
  @override
  void installBackend(BackendRegistry registry) {
    // Упаковка — такое же дело, как копирование, и живёт там же, где формат.
    // Работой, а не командой: обход дерева и байты — по эту сторону границы.
    registry.operation(
      ZipPacking.kind,
      (services) =>
          ZipPacking(staging: services.resolve<StagingArea>(), strings: services.resolve<Strings>()).operation(),
    );

    registry.provider(
      ZipTreeProvider.schemeName,
      // Архив внутри архива сперва оказывается на диске, но где именно —
      // знает не архиватор: место под временные файлы даёт приложение.
      () => TaskOperation<FsNode, TreeProvider>((op, host) {
        final strings = registry.services.resolve<Strings>();
        op.message(strings.tr('Reading {name}…', args: {'name': host.name}));
        return ProviderRegistry.keepUnlessCanceled(
          op,
          ZipTreeProvider.open(
            host,
            staging: registry.services.resolve<StagingArea>(),
            // Зашифрованная запись спросит пароль сама — тем же способом, каким
            // это делает 7z и делает подключение к серверу.
            credentials: registry.services.resolve<Credentials>(),
            // Архив с сервера сперва копируется целиком, и это самая долгая
            // часть открытия: молчать о ней нельзя.
            onBytes:
                (bytes) => op.report(
                  message: strings.tr('Reading {name}…', args: {'name': host.name}),
                  bytesTransferred: bytes,
                ),
            strings: strings,
          ),
        );
      }),
      extensions: ZipTreeProvider.extensions,
    );
  }

  /// Упаковка — такое же действие, как копирование, и живёт там же, где формат:
  /// про zip знает только этот модуль.
  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    registry.command((context) => CreateZipArchiveCommand());
    registry.binding(KeyBinding('Shift-F5', CreateZipArchiveCommand.commandId));
  }
}

/// Русские строки архивов zip.
///
/// Названия уровней сжатия приходят значением (`ZipCompression.title`), а
/// заголовок окна пароля — вопросом от ядра: переводит их тот, кто показывает.
/// Заголовок окна, когда пакуется несколько объектов: их число говорится
/// честно, а склейкой строк по-русски это не сказать.
const Map<String, PluralForms> _plurals = {
  'Create ZIP archive of {n} items': (
    one: 'Создать архив ZIP из {n} объекта',
    few: 'Создать архив ZIP из {n} объектов',
    many: 'Создать архив ZIP из {n} объектов',
  ),
};

const Map<String, String> _russian = {
  'Create ZIP archive': 'Создать архив ZIP',
  'Cannot store the link «{name}» in a zip archive': 'Ссылку «{name}» нельзя сохранить в архиве zip',
  'The link «{name}» points into the directory being packed': 'Ссылка «{name}» ведёт внутрь упаковываемого каталога',
  'The link «{name}» leads nowhere': 'Ссылка «{name}» никуда не ведёт',
  'Zip archives': 'Архивы zip',
  'Mk Zip': 'Zip',
  'Pack the selected items into a new zip archive': 'Упаковать выбранное в новый архив zip',
  'Packing…': 'Упаковка…',
  'Create': 'Создать',
  'Create in': 'Создать в',
  'Archive name': 'Имя архива',
  'Follow symlinks': 'Идти по ссылкам',
  'Compression': 'Сжатие',
  'Store': 'Без сжатия',
  'Fast': 'Быстро',
  'Normal': 'Обычно',
  'Best': 'Плотно',
  'Reading {name}…': 'Чтение {name}…',
  'sending archive': 'отправка архива',
  'Encrypted archive': 'Зашифрованный архив',
  'repacking archive': 'пересборка архива',
  'repacking and sending archive': 'пересборка и отправка архива',
  'Writing to «{name}» repacks the whole archive. Continue?':
      'Запись в «{name}» пересобирает архив целиком. Продолжить?',
  'Writing to «{name}» repacks the whole archive and sends it back{volume}. Continue?':
      'Запись в «{name}» пересобирает архив целиком и отправляет его обратно{volume}. Продолжить?',
};
