import 'package:fc_api/fc_api.dart';

/// Разбор имени со словарём составных расширений.
///
/// `archive.tar.gz` — это архив `tar.gz`, а не `archive.tar` с расширением
/// `gz`. Словарь, а не догадка по числу точек: правило «две точки подряд —
/// составное» ломается на `readme.v2.txt` и на любых версиях в именах.
///
/// Это правило **показа**: им пользуются те, кто рисует колонки и сортирует по
/// расширению. Тот, кто спрашивает «что это за файл», берёт [extensionOf] — и
/// правильно делает: реестру провайдеров составное расширение прямо вредно,
/// `a.tar.gz` монтируется как `gz`, а `tar` разбирается уже внутри.
class CompoundFileNaming implements FileNaming {
  CompoundFileNaming({required this.compound, required this.useBuiltin});

  /// Словарь пользователя — способом узнать, а не значением: настройку правят
  /// в окне, и следующая же перерисовка должна показать новое.
  final List<String> Function() compound;

  /// Учитывать ли встроенный список.
  final bool Function() useBuiltin;

  /// То, что встречается каждый день.
  ///
  /// Список короткий нарочно: словарь — не каталог всех составных расширений
  /// мира, а ответ на «что я вижу каждый день». В длинном однажды окажется то,
  /// что человеку составным не кажется.
  static const List<String> builtin = [
    'tar.gz',
    'tar.bz2',
    'tar.xz',
    'tar.zst',
    'tar.lz4',
    'spec.ts',
    'test.ts',
    'd.ts',
    'min.js',
    'min.css',
    'min.mjs',
    'blade.php',
  ];

  static const FileNaming _reference = ReferenceFileNaming();

  @override
  ({String base, String extension}) split(String name) {
    // Пользовательское впереди встроенного: так своё можно поставить над
    // общим, а не спорить с ним.
    for (final candidate in [...compound(), if (useBuiltin()) ...builtin]) {
      final extension = _matched(name, candidate);
      if (extension != null) {
        return (base: name.substring(0, name.length - extension.length - 1), extension: extension);
      }
    }
    return _reference.split(name);
  }

  /// Подходит ли составное расширение этому имени.
  ///
  /// Совпадение ищется **по границе точки**: `notes.tar.gz` попадает под
  /// `tar.gz`, а `mytar.gz` — нет, у него расширение `gz`. И перед точкой
  /// должно остаться имя: `.tar.gz` — это имя целиком, как `.gitignore`.
  static String? _matched(String name, String candidate) {
    final suffix = candidate.trim();
    if (suffix.isEmpty) {
      return null;
    }
    final tail = '.$suffix';
    if (name.length <= tail.length || !name.toLowerCase().endsWith(tail.toLowerCase())) {
      return null;
    }
    // Возвращается то, что написано в имени, а не в словаре: регистр остаётся
    // человеческим — `Archive.TAR.GZ` покажется как есть.
    return name.substring(name.length - suffix.length);
  }
}
