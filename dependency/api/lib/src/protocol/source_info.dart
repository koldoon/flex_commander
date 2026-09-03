import '../panel/column_spec.dart';
import '../values/provider_capabilities.dart';

/// Снимок источника: что интерфейс знает о нём, не спрашивая.
///
/// **Свойства не спрашивают, их знают.** Ходить за границу за тем, что и так
/// известно, — это оборот порта на каждую отрисовку строки. Снимок едет вместе
/// с состоянием панели и меняется вместе с каталогом: войдя в архив, панель
/// отвечает о нём, а не о том, с чего начинала
/// (`docs/spec/client-server.md`, §4.4).
///
/// Умения перечислены флагами, а не проверками типа: `provider is NodeEditor`
/// на этой стороне невозможен — самого источника здесь нет.
class SourceInfo {
  const SourceInfo({
    required this.scheme,
    this.rootPath = '',
    this.homePath = '',
    this.capabilities = const ProviderCapabilities(),
    this.canWrite = false,
    this.canStream = false,
    this.canReceive = false,
    this.isShellHost = false,
    this.contentKind = files,
    this.columns,
    this.shellLabel = '',
    this.shellProgram = '',
  });

  /// Обычная таблица файлов — то, чем панель показывает каталог.
  static const String files = 'files';

  /// Схема списка находок: по ней его узнают снаружи — например, `Enter` над
  /// находкой, который уводит к ней в её каталог.
  static const String foundScheme = 'found';

  /// Схема путей: `fs`, `zip`, `sftp`.
  final String scheme;

  /// Корень источника и каталог по умолчанию — строками, а не узлами: спросить
  /// их через границу значило бы сделать асинхронным то, что известно раньше
  /// первой панели.
  final String rootPath;
  final String homePath;

  final ProviderCapabilities capabilities;

  /// Дерево можно менять: у источника есть примитивы правки.
  final bool canWrite;

  /// Источник отдаёт содержимое потоком, и принимает его.
  final bool canStream;
  final bool canReceive;

  /// В этом источнике можно завести оболочку.
  final bool isShellHost;

  /// Чем рисовать содержимое панели. Обычный источник о видах не подозревает —
  /// значит, таблица файлов.
  final String contentKind;

  /// Колонки, которых просит сам источник; null — панель показывает свои.
  ///
  /// Просит только тот, кто не каталог: списку находок нужна колонка пути.
  /// Настройку панели это не меняет — уйдя из находок, человек видит те
  /// колонки, что настраивал.
  final ColumnLayout? columns;

  /// Как место называется в оболочке: `localhost` или `user@host`.
  final String shellLabel;

  /// Чем оболочка запускается.
  final String shellProgram;

  @override
  String toString() => 'SourceInfo($scheme)';
}
