import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sftp.dart';

/// Каталог со ссылками читается разом, а не по одной.
///
/// Про каждую ссылку сервер спрашивают дважды — куда ведёт и каталог ли там.
/// Пока эти вопросы шли один за другим, каждый стоил полного оборота:
/// `/usr/bin` со ста пятьюдесятью пятью ссылками открывался девятнадцать
/// секунд на живом сервере (`docs/spec/ssh-listing-speed.md`).
void main() {
  late FakeSftp sftp;
  late SftpTreeProvider provider;

  /// Каталог, где каждая вторая запись — ссылка.
  const links = 40;

  setUp(() {
    sftp = FakeSftp();
    sftp.directory('/srv');
    for (var i = 0; i < links; i++) {
      sftp.file('/srv/файл$i.txt', 'тело');
      sftp.link('/srv/ссылка$i', '/srv/файл$i.txt');
    }
    provider = SftpTreeProvider(target: SshTarget.parse(Uri.parse('ssh://user@host/')), sftp: sftp, homePath: '/');
  });

  Future<DirectoryNode> srv() async => await provider.resolvePath().run('/srv') as DirectoryNode;

  test('вопросы о ссылках идут разом, а не по очереди', () async {
    sftp.answerDelay = const Duration(milliseconds: 10);
    final dir = await srv();

    final watch = Stopwatch()..start();
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
    watch.stop();

    expect(nodes.whereType<LinkNode>(), hasLength(links));
    expect(sftp.peakInFlight, greaterThan(1), reason: 'спрашивали по одному');

    // По очереди это 40 ссылок × 2 вопроса × 10 мс = 800 мс и ни секундой
    // меньше. Разом — на порядок быстрее; берём щедрый запас, чтобы проверка
    // не зависела от расторопности машины.
    expect(watch.elapsedMilliseconds, lessThan(400), reason: 'вопросы всё ещё идут по очереди');
  });

  test('обычные записи сервера не спрашивают вовсе', () async {
    // Первая попытка делила на пачки **все** записи, и ссылки расходились по
    // ним по две-три штуки: пачки снова шли одна за другой, и выигрыш выходил
    // вдвое вместо тридцати.
    final dir = await srv();
    sftp.calls.clear();

    await provider.getDirectoryListing().run(ListingParams(dir));

    final asked = sftp.calls.where((call) => !call.startsWith('list')).length;
    expect(asked, links * 2, reason: 'по два вопроса на ссылку и ни одного на файл');
  });

  test('порядок строк тот же, каким его дал сервер', () async {
    // Спрашивать разом — не значит складывать в порядке ответов: ответы
    // приходят вперемешку, а список должен остаться тем же.
    sftp.answerDelay = const Duration(milliseconds: 1);
    final dir = await srv();
    final fromServer = [for (final entry in await sftp.listDirectory('/srv')) entry.name];

    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));

    expect([for (final node in nodes.skip(1)) node.name], fromServer);
  });

  test('у каждой ссылки своя цель, а не соседняя', () async {
    // Пачки складывают ответы по местам; перепутать их — значит показать
    // человеку неправду о том, куда ведёт ссылка.
    sftp.answerDelay = const Duration(milliseconds: 1);
    final dir = await srv();

    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
    final found = nodes.whereType<LinkNode>().toList();

    expect(found, hasLength(links));
    for (final node in found) {
      expect(node.reference, '/srv/${node.name.replaceFirst('ссылка', 'файл')}.txt');
    }
  });
}
