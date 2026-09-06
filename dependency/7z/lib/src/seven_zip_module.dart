import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'create_archive_command.dart';
import 'seven_zip_cli.dart';
import 'seven_zip_pack.dart';
import 'seven_zip_settings.dart';
import 'seven_zip_tree_provider.dart';

/// Архивы 7z как дерево — и то, чем их упаковывают.
///
/// Один класс на обе стороны: половины у модуля разные, а модуль один — тот же
/// идентификатор, тот же раздел настроек, та же строка в справке.
///
/// Модуль ставится и там, где программы 7-Zip нет: схема остаётся, а обращение
/// к архиву кончается внятной ошибкой. Молчаливое «ничего не происходит» было
/// бы хуже — пользователю неоткуда узнать, чего не хватает.
class SevenZipArchiver implements FcBackendModule, FcFrontendModule {
  const SevenZipArchiver();

  @override
  String get id => 'fc.7z_archiver';

  @override
  String get title => '7z archives';

  @override
  void installBackend(BackendRegistry registry) {
    // Раздел настроек берётся здесь, а не в фабрике: реестр отдаёт раздел
    // тому, кто устанавливается сейчас, и спрошенный позже он оказался бы
    // чужим. Содержимое раздела к моменту вызова фабрики уже прочитано.
    final settings = registry.settings;

    // Программа одна на приложение: она запоминает, где лежит и какие ключи
    // понимает, и выяснять это заново на каждом архиве незачем.
    registry.service<SevenZipCli>(
      (services) => SevenZipCli(
        processes: services.resolve<ProcessRunner>(),
        executable: settings.section(SevenZipSettings.new).binary,
      ),
    );

    // Упаковка — работа ядра: обход дерева и запуск программы по эту сторону
    // границы.
    registry.operation(
      SevenZipPacking.kind,
      (services) =>
          SevenZipPacking(staging: services.resolve<StagingArea>(), cli: services.resolve<SevenZipCli>()).operation(),
    );

    registry.provider(
      SevenZipTreeProvider.schemeName,
      // Архив внутри архива сперва оказывается на диске, но где именно —
      // знает не архиватор: место под временные файлы даёт приложение.
      () => TaskOperation<FsNode, TreeProvider>((op, host) {
        final strings = registry.services.resolve<Strings>();
        op.message(strings.tr('Reading {name}…', args: {'name': host.name}));
        return ProviderRegistry.keepUnlessCanceled(
          op,
          SevenZipTreeProvider.open(
            host,
            staging: registry.services.resolve<StagingArea>(),
            cli: registry.services.resolve<SevenZipCli>(),
            // Архив под паролем спросит его сам — тем же способом, каким это
            // делает подключение к серверу.
            credentials: registry.services.resolve<Credentials>(),
            // Копирование архива во временный файл — самая долгая часть
            // открытия, и о ней стоит рассказывать.
            onBytes:
                (bytes) => op.report(
                  message: strings.tr('Reading {name}…', args: {'name': host.name}),
                  bytesTransferred: bytes,
                ),
            strings: strings,
          ),
        );
      }),
      extensions: SevenZipTreeProvider.extensions,
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    // Раздел тот же, что у ядровой половины: имя одно на модуль, а файл
    // настроек принадлежит ядру.
    final settings = registry.settings;

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.text(
          'binary',
          title: strings.tr('7z program'),
          hint: strings.tr('found on PATH'),
          description: strings.tr('Full path — for when it is installed somewhere unusual'),
          note: strings.tr('Applies to the next archive opened'),
          read: () => settings.section(SevenZipSettings.new).binary,
          write: (value) => settings.section(SevenZipSettings.new).binary = value,
        ),
      ], save: settings.save);
    });

    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат: про 7z знает только этот модуль.
    registry.command((context) => CreateSevenZipArchiveCommand());
    registry.binding(KeyBinding('Shift-F7', CreateSevenZipArchiveCommand.commandId));
  }
}

/// Русские строки архивов 7z.
/// Заголовок окна, когда пакуется несколько объектов.
const Map<String, PluralForms> _plurals = {
  'Create 7z archive of {n} items': (
    one: 'Создать архив 7z из {n} объекта',
    few: 'Создать архив 7z из {n} объектов',
    many: 'Создать архив 7z из {n} объектов',
  ),
};

const Map<String, String> _russian = {
  'Create 7z archive': 'Создать архив 7z',
  '7z archives': 'Архивы 7z',
  'Mk 7z': '7z',
  'Pack the selected items into a new 7z archive': 'Упаковать выбранное в новый архив 7z',
  'Packing…': 'Упаковка…',
  'Create': 'Создать',
  'Create in': 'Создать в',
  'Archive name': 'Имя архива',
  'Follow symlinks': 'Идти по ссылкам',
  'Compression': 'Сжатие',
  'Reading {name}…': 'Чтение {name}…',
  'sending archive': 'отправка архива',
  'Encrypted archive': 'Зашифрованный архив',
  'Writing to «{name}» rewrites the whole archive. Continue?':
      'Запись в «{name}» перезаписывает архив целиком. Продолжить?',
  'Writing to «{name}» rewrites the whole archive and sends it back{volume}. Continue?':
      'Запись в «{name}» перезаписывает архив целиком и отправляет его обратно{volume}. Продолжить?',

  // Настройки.
  '7z program': 'Программа 7z',
  'found on PATH': 'найдена в PATH',
  'Full path — for when it is installed somewhere unusual': 'Полный путь — если она стоит в необычном месте',
  'Applies to the next archive opened': 'Подействует на следующий открытый архив',
};
