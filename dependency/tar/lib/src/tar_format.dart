/// Что получится на выходе.
///
/// Выбор из двух, а не степень сжатия: у tar её нет вовсе — сжимает не он, а
/// gzip поверх него, и уровень там почти ни на что не влияет.
enum TarFormat {
  plain('.tar', 'tar'),
  gzip('.tar.gz', 'tar.gz'),

  /// То же, что [gzip], и отличается только именем файла.
  ///
  /// Отдельным пунктом, а не догадкой по набранному расширению: `.tgz` живёт
  /// там, где длинные имена неудобны, и человек, которому нужен именно он,
  /// иначе получал бы `.tar.gz` молча.
  tgz('.tgz', 'tgz');

  const TarFormat(this.extension, this.title);

  /// Чем кончается имя архива.
  final String extension;

  /// Название для человека.
  final String title;

  /// Заворачивается ли архив в gzip. У `.tar` — нет, у остальных — да.
  bool get compressed => this != TarFormat.plain;

  static TarFormat byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => TarFormat.gzip);
}
