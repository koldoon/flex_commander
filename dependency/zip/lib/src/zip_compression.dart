/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum ZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 6),
  best('Best', 9);

  const ZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень deflate: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static ZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => ZipCompression.normal);
}
