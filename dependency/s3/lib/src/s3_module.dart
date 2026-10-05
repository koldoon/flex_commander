import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 's3_address.dart';
import 's3_tree_provider.dart';

/// Хранилища S3 по адресу `s3://` и `s3+http://` (`docs/spec/s3.md`).
///
/// Только половина ядра, как у FTP: своих окон и команд у источника нет —
/// схему он объявляет, а дальше работают общие команды.
class S3FileSystem implements FcBackendModule {
  const S3FileSystem();

  @override
  String get id => 'fc.s3';

  @override
  String get title => 'S3 storage';

  @override
  void installBackend(BackendRegistry registry) {
    registry.strings('ru', _russian);

    for (final scheme in const [S3Target.scheme, S3Target.plainScheme]) {
      registry.addressProvider(
        scheme,
        () => TaskOperation<Uri, TreeProvider>((op, address) {
          final strings = registry.services.resolve<Strings>();
          // Только схема и хост: в адресе бывает секрет, а сообщение видно.
          op.message(strings.tr('Connecting to {where}…', args: {'where': '$scheme://${address.host}'}));
          return ProviderRegistry.keepUnlessCanceled(
            op,
            S3TreeProvider.open(address, credentials: registry.services.resolve<Credentials>(), strings: strings),
          );
        }),
      );
    }
  }
}

const Map<String, String> _russian = {
  'S3 storage': 'Хранилище S3',
  'S3 authentication': 'Вход в хранилище S3',
  'Access key ID': 'Идентификатор ключа доступа',
  'Secret access key': 'Секретный ключ',
  'Connecting to {where}…': 'Подключение к {where}…',
  'Reading {path}…': 'Чтение {path}…',
  'Reading {path}… {count}': 'Чтение {path}… {count}',
};
