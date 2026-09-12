import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

/// Подмена приложения собой же — новой сборкой.
///
/// Приложение не может перезаписать себя, пока работает: каталог `.app` занят,
/// а после подмены процесс исполнял бы уже несуществующий код. Поэтому
/// последний шаг делает **помощник** — короткий сценарий, который мы запускаем
/// и отпускаем, а сами закрываемся (`docs/spec/self-update.md`, §6).
class UpdateInstall {
  const UpdateInstall({required this.processes, required this.workspace});

  final ProcessRunner processes;

  /// Где распаковывать: каталог рядом с кешем загрузок, не в бандле.
  final Directory workspace;

  /// Распаковывает выпуск и возвращает новый `.app`.
  ///
  /// Распаковывает `ditto`, а не свой разбор zip: он системный, знает про
  /// ресурсы и права macOS и кладёт бандл ровно таким, каким его упаковали —
  /// тем же `ditto` на сборке.
  Future<Directory> unpack(File archive) async {
    final into = Directory(p.join(workspace.path, 'unpacked'));
    if (await into.exists()) {
      await into.delete(recursive: true);
    }
    await into.create(recursive: true);

    final outcome = await processes.run('/usr/bin/ditto', ['-x', '-k', archive.path, into.path]);
    if (!outcome.ok) {
      throw FsError(archive.path, FsErrorKind.io);
    }

    final bundles =
        await into
            .list()
            .where((entry) => entry is Directory && entry.path.endsWith('.app'))
            .cast<Directory>()
            .toList();
    // Ровно один: пусто — упаковали не то, несколько — непонятно, что из этого
    // мы. Гадать на месте подмены приложения нельзя.
    if (bundles.length != 1) {
      throw FsError(archive.path, FsErrorKind.notSupported);
    }
    return bundles.first;
  }

  /// Просит помощника подменить [target] на [replacement] и открыть новое.
  ///
  /// Возвращается сразу: дальше приложение обязано закрыться само — помощник
  /// ждёт именно этого.
  Future<void> handOver({required Directory replacement, required String target, int? pid}) async {
    final backup = '$target$backupSuffix';

    // Пути уходят **аргументами**, а не склейкой в текст сценария: в них
    // бывают пробелы, кавычки и что угодно ещё — имя тома человек выбирает
    // сам.
    await processes.detach('/bin/sh', ['-c', _script, 'fc-update', '${pid ?? 0}', replacement.path, target, backup]);
  }

  /// Приставка к имени отложенной сборки.
  ///
  /// Прежнюю не удаляем в тот же миг: если новая не запустится, вернуться
  /// будет некуда. Убирает её следующий удачный запуск — [forgetBackup].
  static const String backupSuffix = '.previous';

  /// Убрать отложенную сборку рядом с собой: раз мы запустились, возвращаться
  /// не к чему.
  static Future<void> forgetBackup(String bundlePath) async {
    final backup = Directory('$bundlePath$backupSuffix');
    if (await backup.exists()) {
      await backup.delete(recursive: true);
    }
  }

  /// Сам помощник — тот же текст, что уходит в `/bin/sh`.
  ///
  /// Открыт наружу ради проверки: подставкой его не проверить, вся его суть в
  /// том, что делает оболочка, — и гоняется он в тесте на настоящих каталогах.
  String get helperScript => _script;

  /// Сам помощник.
  ///
  /// Ждёт нашего выхода, меняет каталоги местами и открывает новую сборку.
  /// Если подменить не вышло — возвращает прежнюю на место: остаться без
  /// приложения человек не должен.
  static const String _script = '''
set -e
pid="\$1"; new="\$2"; target="\$3"; backup="\$4"

# Ждём, пока приложение закроется: занятый каталог не подменить.
i=0
while kill -0 "\$pid" 2>/dev/null && [ \$i -lt 300 ]; do
  sleep 0.2
  i=\$((i + 1))
done

rm -rf "\$backup"
mv "\$target" "\$backup"
if ! mv "\$new" "\$target"; then
  mv "\$backup" "\$target"
  exit 1
fi

# Открыть не вышло — не беда: подмена уже состоялась, и приложение откроют
# руками. Ронять помощника на последнем шаге незачем.
open -n "\$target" || true
''';
}
