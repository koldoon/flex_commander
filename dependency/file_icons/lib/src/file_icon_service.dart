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
    if (_systemIcons == null) {
      return null;
    }

    final question = _questionOf(entry, pixels);
    if (_system.containsKey(question.key)) {
      final image = _system[question.key];
      return image == null ? null : IconPicture(image);
    }

    needs.add(_ask(question, pixels));
    return null;
  }

  Future<void> _ask(_Question question, int pixels) {
    final asking = _asking[question.key];
    if (asking != null) {
      return asking;
    }
    final future = _fetch(question, pixels);
    _asking[question.key] = future;
    return future;
  }

  Future<void> _fetch(_Question question, int pixels) async {
    Uint8List? bytes;
    try {
      final icons = _systemIcons!;
      bytes = switch (question.ask) {
        _Ask.path => await icons.forPath(question.about, pixels: pixels),
        _Ask.extension => await icons.forExtension(question.about, pixels: pixels),
        _Ask.folder => await icons.forKind(SystemIconKind.folder, pixels: pixels),
        _Ask.file => await icons.forKind(SystemIconKind.file, pixels: pixels),
      };
    } on Object {
      // Канала нет, платформа не умеет, путь исчез — иконка возьмётся
      // следующим правилом, и это не повод падать.
      bytes = null;
    }

    _asking.remove(question.key);
    _remember(question.key, bytes == null ? null : MemoryImage(bytes));
  }

  /// О чём спросить систему — по убыванию точности и по возрастанию цены.
  ///
  /// **Путь** знает всё: своё лицо пакета (`*.app`), тома, назначенную иконку.
  /// Но стоит вопроса на каждую строку, и есть он только у настоящей файловой
  /// системы.
  ///
  /// **Расширение** отвечает за обычный файл целиком, и пути для этого не
  /// нужно: тысяча `.txt` в каталоге — один вопрос вместо тысячи, и тем же
  /// вопросом спрашивают про файл на сервере и в архиве. Значок при этом
  /// здешний — чужих сопоставлений нам никто не расскажет, да человек и
  /// смотрит на свой экран.
  ///
  /// **Род** — последнее, что остаётся: папка или просто файл.
  static _Question _questionOf(FileEntry entry, int pixels) {
    if (entry.realPath.isNotEmpty && _byPath(entry)) {
      return _Question(_Ask.path, 'p:${entry.realPath}@$pixels', entry.realPath);
    }

    final extension = extensionOf(entry.name).toLowerCase();
    if (!entry.canEnter && extension.isNotEmpty) {
      return _Question(_Ask.extension, 'e:$extension@$pixels', extension);
    }

    return entry.canEnter ? _Question(_Ask.folder, 'k:folder@$pixels', '') : _Question(_Ask.file, 'k:file@$pixels', '');
  }

  /// Спрашивать ли по пути — при условии, что путь вообще есть.
  ///
  /// Свой значок бывает у каталогов, исполняемых файлов и файлов без
  /// расширения; у остальных он зависит только от расширения.
  static bool _byPath(FileEntry entry) =>
      entry.kind != EntryKind.file || entry.executable || extensionOf(entry.name).isEmpty;

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

/// Чем спрашивают систему.
enum _Ask { path, extension, folder, file }

/// Вопрос к системе: чем спрашивать, под каким ключом помнить ответ и о чём
/// именно речь — путь или расширение; у рода это пусто.
class _Question {
  const _Question(this.ask, this.key, this.about);

  final _Ask ask;
  final String key;
  final String about;
}
