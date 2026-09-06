import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'sftp_tree_provider.dart';

/// Файловая система чужой машины по SSH.
///
/// Первый источник, открываемый по адресу: панель встаёт на сервер целиком,
/// а не монтирует его звеном пути. Ядру знать об этом нечего — модуль
/// объявляет схему, а всё остальное делают общие команды.
class SshFileSystem implements FcBackendModule {
  const SshFileSystem();

  @override
  String get id => 'fc.ssh';

  @override
  String get title => 'SSH file system';

  @override
  void installBackend(BackendRegistry registry) {
    registry.strings('ru', _russian);

    // Два имени одного и того же: `ssh://` привычнее по командной строке,
    // `sftp://` — по файловым менеджерам. Разводить их незачем — работа идёт
    // по одному и тому же протоколу.
    for (final scheme in const ['ssh', 'sftp']) {
      registry.addressProvider(
        scheme,
        // Пароль и парольная фраза спрашиваются тем же окном, что и пароль
        // архива: модуль не знает, ни как спрашивают, ни где помнят ответ.
        () => TaskOperation<Uri, TreeProvider>((op, address) {
          // Ни адреса целиком, ни authority: в них бывает пароль, набранный
          // прямо в строке. Хост и протокол говорят ровно то, что нужно.
          final strings = registry.services.resolve<Strings>();
          op.message(strings.tr('Connecting to {where}…', args: {'where': '$scheme://${address.host}'}));
          return ProviderRegistry.keepUnlessCanceled(
            op,
            SftpTreeProvider.open(
              address,
              credentials: registry.services.resolve<Credentials>(),
              // Необязательно и лениво: службу объявляет ядро, а спрашивают её
              // только тогда, когда сервер отказал в записи.
              elevation: () => registry.services.resolveAll<ElevatedWrites>().firstOrNull,
              strings: strings,
            ),
          );
        }),
      );
    }
  }
}

/// Русские строки источника по SSH.
///
/// Заголовки окон пароля приходят значением (`CredentialRequest.title`), а не
/// литералом в вызове: спрашивает эта сторона, а показывает та.
const Map<String, String> _russian = {
  'SSH file system': 'Файлы по SSH',
  'Reading {path}…': 'Чтение {path}…',
  'Connecting to {where}…': 'Подключение к {where}…',
  'Write': 'Записать',
  'SSH authentication': 'Вход по SSH',
  'Encrypted key': 'Зашифрованный ключ',
};
