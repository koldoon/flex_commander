import 'dart:collection';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'file_icon_settings.dart';
import 'picture_files.dart';

/// Выбор иконки по правилам.
///
/// Спецификация — `docs/spec/file-icons.md`.
class FileIconService implements FileIcons {
  FileIconService({
    required FileIconSettings Function() settings,
    ContentTypes? contentTypes,
    SystemIcons? systemIcons,
    PictureFiles? pictures,
    int cacheLimit = defaultCacheLimit,
  }) : _settings = settings,
       _contentTypes = contentTypes,
       _systemIcons = systemIcons,
       _pictures = pictures ?? PictureFiles(),
       _cacheLimit = cacheLimit;

  /// Сколько значков системы помним. Ключей мало (десятки расширений плюс
  /// пакеты), но ходьба по дереву не должна копить их без конца.
  static const int defaultCacheLimit = 512;

  /// Сколько раз перепроверяем список правил, пока недостающее приезжает.
  ///
  /// Больше двух шагов цепочка не бывает: сперва тип по содержимому, потом —
  /// значок системы у правила, которое этим типом и совпало. Предел стоит не
  /// ради них, а ради того, чтобы вопрос, на который никогда не ответят, не
  /// крутил колесо вечно.
  static const int _maxRounds = 3;

  final FileIconSettings Function() _settings;
  final ContentTypes? _contentTypes;
  final SystemIcons? _systemIcons;
  final PictureFiles _pictures;
  final int _cacheLimit;

  /// Значки системы: ключ → чем рисовать. null в значении — спрашивали, и
  /// значка нет; тогда правило с `system` не срабатывает.
  final LinkedHashMap<String, ImageProvider?> _system = LinkedHashMap();

  /// Спрошенное, но не отвеченное: второй вопрос про то же ждёт первого.
  final Map<String, Future<void>> _asking = {};

  @override
  double get size => _settings().size.toDouble();

  @override
  ({FileIcon now, Future<FileIcon>? later}) resolve(
    FileEntry entry, {
    required int pixels,
    Content Function()? open,
    bool Function()? stillWanted,
  }) {
    final needs = <Future<void>>[];
    final now = _walk(entry, pixels, open, stillWanted, needs);
    if (needs.isEmpty) {
      return (now: now, later: null);
    }
    return (now: now, later: _refine(entry, pixels, open, stillWanted, now, needs));
  }

  /// Пройти правила сверху вниз. Первое совпавшее выигрывает.
  ///
  /// Всё, чего не хватило для проверки или для рисования, складывается в
  /// [needs] — и правило считается не совпавшим: пусть сработает следующее, а
  /// когда недостающее приедет, список пройдут заново.
  FileIcon _walk(
    FileEntry entry,
    int pixels,
    Content Function()? open,
    bool Function()? stillWanted,
    List<Future<void>> needs,
  ) {
    final settings = _settings();
    final type = _contentTypes?.known(entry);

    for (final rule in settings.rules) {
      if (rule.when.needsContent && type == null) {
        _wantType(entry, open, stillWanted, needs);
        continue;
      }
      if (!rule.when.matches(entry, type: type?.id, group: type?.group.name)) {
        continue;
      }
      final icon = _iconOf(rule.icon, entry, pixels, needs);
      if (icon != null) {
        return icon;
      }
    }

    // Флаг ниже правил: «покажи как в Finder» — умолчание, которое правилами
    // перекрывают, а не наоборот.
    if (settings.system) {
      final icon = _systemIcon(entry, pixels, needs);
      if (icon != null) {
        return icon;
      }
    }

    // Встроенный хвост — тот же, которым панель рисует иконки без модуля
    // правил вовсе. Он и живёт там, где его видят оба.
    return FileIcon.builtIn(entry);
  }

  FileIcon? _iconOf(IconSource source, FileEntry entry, int pixels, List<Future<void>> needs) => switch (source) {
    GlyphRoleSource(:final role) => IconRole(role),
    GlyphCodeSource(:final codePoint) => IconGlyph(codePoint),
    PictureSource(:final path) => switch (_pictures.of(path)) {
      final ImageProvider image => IconPicture(image),
      null => null,
    },
    SystemIconSource() => _systemIcon(entry, pixels, needs),
  };

  /// Завести определение типа, если его есть кому вести.
  ///
  /// Каталоги и ссылки не спрашиваются вовсе: там нечего читать, и запрос
  /// вернулся бы пустым на каждом круге.
  void _wantType(FileEntry entry, Content Function()? open, bool Function()? stillWanted, List<Future<void>> needs) {
    final types = _contentTypes;
    if (types == null || open == null || entry.kind != EntryKind.file) {
      return;
    }
    needs.add(types.detect(entry, open, stillWanted: stillWanted));
  }

  FileIcon? _systemIcon(FileEntry entry, int pixels, List<Future<void>> needs) {
    // Внутри архива и на сервере у строки нет имени, которое что-то значит для
    // системы, — спрашивать не о чем.
    if (_systemIcons == null || entry.realPath.isEmpty) {
      return null;
    }

    final key = _keyOf(entry, pixels);
    if (_system.containsKey(key)) {
      final image = _system[key];
      return image == null ? null : IconPicture(image);
    }

    needs.add(_ask(key, entry, pixels));
    return null;
  }

  Future<void> _ask(String key, FileEntry entry, int pixels) {
    final asking = _asking[key];
    if (asking != null) {
      return asking;
    }
    final future = _fetch(key, entry, pixels);
    _asking[key] = future;
    return future;
  }

  Future<void> _fetch(String key, FileEntry entry, int pixels) async {
    Uint8List? bytes;
    try {
      bytes =
          _byPath(entry)
              ? await _systemIcons!.forPath(entry.realPath, pixels: pixels)
              : await _systemIcons!.forExtension(extensionOf(entry.name), pixels: pixels);
    } on Object {
      // Канала нет, платформа не умеет, путь исчез — иконка возьмётся
      // следующим правилом, и это не повод падать.
      bytes = null;
    }

    _asking.remove(key);
    _remember(key, bytes == null ? null : MemoryImage(bytes));
  }

  /// Спрашивать по пути или по расширению.
  ///
  /// Свой значок бывает у каталогов (пакеты `*.app`), исполняемых файлов и
  /// файлов без расширения; у остальных он зависит только от расширения — и
  /// тогда тысяча `.txt` в каталоге стоит одного вопроса системе, а не тысячи.
  static bool _byPath(FileEntry entry) =>
      entry.kind != EntryKind.file || entry.executable || extensionOf(entry.name).isEmpty;

  static String _keyOf(FileEntry entry, int pixels) =>
      _byPath(entry) ? 'p:${entry.realPath}@$pixels' : 'e:${extensionOf(entry.name).toLowerCase()}@$pixels';

  void _remember(String key, ImageProvider? image) {
    _system[key] = image;
    while (_system.length > _cacheLimit) {
      _system.remove(_system.keys.first);
    }
  }

  /// Дождаться недостающего и пройти правила заново — столько раз, сколько
  /// нужно, но не больше [_maxRounds].
  Future<FileIcon> _refine(
    FileEntry entry,
    int pixels,
    Content Function()? open,
    bool Function()? stillWanted,
    FileIcon current,
    List<Future<void>> pending,
  ) async {
    var icon = current;
    var waiting = pending;

    for (var round = 0; round < _maxRounds; round++) {
      await Future.wait(waiting);
      if (stillWanted?.call() == false) {
        return icon;
      }

      final needs = <Future<void>>[];
      icon = _walk(entry, pixels, open, stillWanted, needs);
      if (needs.isEmpty) {
        return icon;
      }
      waiting = needs;
    }

    return icon;
  }
}
