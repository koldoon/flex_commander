import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'archive_extract.dart';
import 'extract_here_command.dart';
import 'pack_here_command.dart';

/// Архив по месту: распаковать рядом с ним самим и упаковать в свою же панель
/// (`docs/spec/archive-here.md`).
///
/// Форматов модуль не знает вовсе: что раскрывается, говорит строка
/// (`FileEntry.mountsAsBranch`), а как именно — вложенный провайдер того
/// модуля, который этот формат принёс.
class ArchiveHere implements FcBackendModule, FcFrontendModule {
  const ArchiveHere();

  @override
  String get id => 'fc.archive_here';

  @override
  String get title => 'Archives in place';

  @override
  void installBackend(BackendRegistry registry) {
    // Работа, а не команда: монтирование архива и байты — по эту сторону
    // границы. Каталог заводится по оглавлению, а прочитать его может только
    // та сторона, где живут узлы (§3.2).
    registry.operation(
      ArchiveExtraction.kind,
      (services) =>
          ArchiveExtraction(
            registry: services.resolve<ProviderRegistry>(),
            naming: services.resolve<FileNaming>(),
          ).operation(),
      writes: true,
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    registry.command((context) => ExtractHereCommand());
    registry.binding(KeyBinding('Alt-F9', ExtractHereCommand.commandId, context: KeyContext.panel));

    // Формат выбирается в окне из объявленного другими модулями: сам этот
    // модуль не знает ни одного (§4).
    registry.command((context) => PackHereCommand(context.resolve<Packers>()));
    registry.binding(KeyBinding('Alt-F5', PackHereCommand.commandId, context: KeyContext.panel));
  }
}

const Map<String, PluralForms> _plurals = {
  'Extract {n} archives': (
    one: 'Распаковать {n} архив',
    few: 'Распаковать {n} архива',
    many: 'Распаковать {n} архивов',
  ),
};

const Map<String, String> _russian = {
  'Archives in place': 'Архивы по месту',
  'Extract here': 'Распаковать сюда',
  'Extract': 'Распаковать',
  'Unpack the archive into the directory where it lies': 'Разложить архив там же, где он лежит',
  'Extracting…': 'Распаковка…',
  'Pack here': 'Упаковать сюда',
  'Pack the selected items into an archive in this very panel': 'Упаковать выбранное в архив в этой же панели',
  'Packing…': 'Упаковка…',
  'Format': 'Формат',
  'failed': 'не удалась',
};
