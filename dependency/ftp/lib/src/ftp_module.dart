import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'ftp_address.dart';
import 'ftp_tree_provider.dart';

/// Файлы по FTP.
///
/// Второй источник, открываемый по адресу: панель встаёт на сервер целиком, а
/// не монтирует его звеном пути. Ядру знать об этом нечего — модуль объявляет
/// схему, а всё остальное делают общие команды
/// (`docs/spec/ftp.md`).
///
/// Экранной половины нет вовсе: своих окон и команд у источника не бывает.
class FtpFileSystem implements FcBackendModule {
  const FtpFileSystem();

  @override
  String get id => 'fc.ftp';

  @override
  String get title => 'FTP file system';

  @override
  void installBackend(BackendRegistry registry) {
    registry.strings('ru', _russian);

    // Две схемы одного протокола, и разница между ними существенная: `ftps`
    // шифрует, `ftp` — нет. Решает её человек, а не догадка по ответу `FEAT`:
    // сервер объявляет `AUTH TLS` и тут же от него отказывается, так что
    // «попробуем, вдруг выйдет» означало бы молчаливый откат к открытому
    // паролю (`docs/spec/ftp.md`, §3.2).
    for (final scheme in const [FtpTarget.scheme, FtpTarget.secureScheme]) {
      registry.addressProvider(
        scheme,
        () => TaskOperation<Uri, TreeProvider>((op, address) {
          // Ни адреса целиком, ни authority: в них бывает пароль, набранный
          // прямо в строке. Хост и протокол говорят ровно то, что нужно.
          final strings = registry.services.resolve<Strings>();
          op.message(strings.tr('Connecting to {where}…', args: {'where': '$scheme://${address.host}'}));
          return ProviderRegistry.keepUnlessCanceled(
            op,
            FtpTreeProvider.open(address, credentials: registry.services.resolve<Credentials>(), strings: strings),
          );
        }),
      );
    }
  }
}

/// Русские строки источника по FTP.
///
/// Заголовок окна пароля приходит значением (`CredentialRequest.title`), а не
/// литералом в вызове: спрашивает эта сторона, а показывает та.
const Map<String, String> _russian = {
  'FTP file system': 'Файлы по FTP',
  'FTP authentication': 'Вход на FTP-сервер',
  'Connecting to {where}…': 'Подключение к {where}…',
  'Reading {path}…': 'Чтение {path}…',
};
