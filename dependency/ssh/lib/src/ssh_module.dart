import 'package:fc_api/fc_api.dart';

import 'sftp_tree_provider.dart';

/// Файловая система чужой машины по SSH.
///
/// Первый источник, открываемый по адресу: панель встаёт на сервер целиком,
/// а не монтирует его звеном пути. Ядру знать об этом нечего — модуль
/// объявляет схему, а всё остальное делают общие команды.
class SshFileSystem implements FcModule {
  const SshFileSystem();

  @override
  String get id => 'fc.ssh';

  @override
  String get title => 'SSH file system';

  @override
  void install(FcRegistry registry) {
    // Два имени одного и того же: `ssh://` привычнее по командной строке,
    // `sftp://` — по файловым менеджерам. Разводить их незачем — работа идёт
    // по одному и тому же протоколу.
    for (final scheme in const ['ssh', 'sftp']) {
      registry.addressProvider(
        scheme,
        // Пароль и парольная фраза спрашиваются тем же окном, что и пароль
        // архива: модуль не знает, ни как спрашивают, ни где помнят ответ.
        (address) => SftpTreeProvider.open(address, credentials: registry.services.resolve<Credentials>()),
      );
    }
  }
}
