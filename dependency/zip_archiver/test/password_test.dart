import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip_archiver/fc_zip_archiver.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Защищённый zip: на настоящих архивах, а не на подставках.
///
/// Заготовки лежат в `test/assets` и собраны заранее — библиотека умеет
/// расшифровывать, но не зашифровывать, поэтому сделать их на ходу нельзя.
/// Пароль у обоих `secret`, внутри один файл `secret.txt` со словом «секрет».
///
/// Два вида шифрования не прихоть: ведут они себя **по-разному**. AES честно
/// сообщает о неверном пароле, а ZipCrypto библиотека расшифровывает молча и
/// отдаёт мусор — там неверный пароль ловится только контрольной суммой.
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
    return (await local.resolvePath(target).result)!;
  }

  Future<ZipTreeProvider> open(String name, FakeCredentials credentials) async {
    final provider =
        await ZipTreeProvider.open(await fixture(name), credentials: credentials, staging: LocalStagingArea(root: temp))
            as ZipTreeProvider;
    addTearDown(provider.dispose);
    return provider;
  }

  Future<String> readSecret(ZipTreeProvider zip) async {
    final node = (await zip.resolvePath('/secret.txt').result)!;
    final chunks = await (await zip.openRead(node)).toList();
    return utf8.decode([for (final chunk in chunks) ...chunk]).trim();
  }

  for (final name in ['aes.zip', 'zipcrypto.zip']) {
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
        final credentials = FakeCredentials(answers: ['secret']);
        final zip = await open(name, credentials);

        expect(await readSecret(zip), 'секрет');
        expect(credentials.asked, hasLength(1));
        expect(credentials.asked.single.title, 'Encrypted archive');
      });

      test('неверный пароль — второй вопрос, уже с пометкой', () async {
        final credentials = FakeCredentials(answers: ['мимо', 'secret']);
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
        final credentials = FakeCredentials(answers: ['secret']);
        final zip = await open(name, credentials);

        await readSecret(zip);
        await readSecret(zip);
        await readSecret(zip);

        expect(credentials.asked, hasLength(1));
      });
    });
  }
}
