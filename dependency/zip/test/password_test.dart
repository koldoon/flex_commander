import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Защищённый zip: на настоящих архивах, а не на подставках.
///
/// Заготовки лежат в `test/assets` и собраны заранее — библиотека умеет
/// расшифровывать, но не зашифровывать, поэтому сделать их на ходу нельзя.
/// Пароль у обоих `secret`, внутри один файл `secret.txt` со словом «секрет».
///
/// Три заготовки не прихоть: ведут они себя **по-разному**.
///
/// * `aes.zip` — AES256: библиотека честно сообщает о неверном пароле.
/// * `zipcrypto.zip` — ZipCrypto: молча расшифровывает в мусор, и неверный
///   пароль ловится только контрольной суммой.
/// * `cyrillic.zip` — пароль не из латиницы: библиотека выводит ключ из кодов
///   UTF-16, а архиваторы кладут байты UTF-8, и без перевода такой архив не
///   открывается никаким паролем.
/// * `descriptor.zip` — тот же ZipCrypto, но собранный системным `zip`:
///   размеры записи лежат в хвосте (бит 3 общих признаков), и распаковщик,
///   получив ещё зашифрованные байты, падает с «Filter error, bad data».
///   Именно на таком архиве первое копирование когда-то кончалось ошибкой
///   ввода-вывода вместо вопроса о пароле.
void main() {
  late Directory temp;
  late LocalTreeProvider local;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fc_zip_password');
    local = LocalTreeProvider();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Копия заготовки: провайдер открывает архив по настоящему пути.
  Future<FsNode> fixture(String name) async {
    final target = p.join(temp.path, name);
    File(p.join('test', 'assets', name)).copySync(target);
    return (await local.resolvePath().run(target))!;
  }

  Future<ZipTreeProvider> open(String name, FakeCredentials credentials) async {
    final provider =
        await ZipTreeProvider.open(await fixture(name), credentials: credentials, staging: LocalStagingArea(root: temp))
            as ZipTreeProvider;
    addTearDown(provider.dispose);
    return provider;
  }

  Future<String> readSecret(ZipTreeProvider zip) async {
    final node = (await zip.resolvePath().run('/secret.txt'))!;
    final chunks = await (await zip.openRead(node)).toList();
    return utf8.decode([for (final chunk in chunks) ...chunk]).trim();
  }

  // Заготовка → пароль к ней.
  const fixtures = {
    'aes.zip': 'secret',
    'zipcrypto.zip': 'secret',
    'descriptor.zip': 'secret',
    'cyrillic.zip': 'тайна',
  };

  fixtures.forEach((name, secret) {
    group(name, () {
      test('оглавление читается и без пароля', () async {
        final credentials = FakeCredentials();
        final zip = await open(name, credentials);

        // Шифруется содержимое, а не имена: спрашивать пароль ради дерева
        // незачем, и панель показывает архив сразу.
        expect(await zip.listChildren(zip.rootDirectory), isNotEmpty);
        expect(credentials.asked, isEmpty);
      });

      test('содержимое спрашивает пароль и расшифровывается', () async {
        final credentials = FakeCredentials(answers: [secret]);
        final zip = await open(name, credentials);

        expect(await readSecret(zip), 'секрет');
        expect(credentials.asked, hasLength(1));
        expect(credentials.asked.single.title, 'Encrypted archive');
      });

      test('неверный пароль — второй вопрос, уже с пометкой', () async {
        final credentials = FakeCredentials(answers: ['мимо', secret]);
        final zip = await open(name, credentials);

        expect(await readSecret(zip), 'секрет');
        expect(credentials.asked, hasLength(2));
        expect(credentials.asked.last.retry, isTrue);
      });

      test('отказ — отказ в доступе, а не мусор вместо файла', () async {
        final credentials = FakeCredentials();
        final zip = await open(name, credentials);

        await expectLater(
          readSecret(zip),
          throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.permissionDenied)),
        );
      });

      test('пароль спрашивается один раз на архив', () async {
        final credentials = FakeCredentials(answers: [secret]);
        final zip = await open(name, credentials);

        await readSecret(zip);
        await readSecret(zip);
        await readSecret(zip);

        expect(credentials.asked, hasLength(1));
      });
    });
  });
}
