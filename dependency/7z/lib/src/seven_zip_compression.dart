/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum SevenZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 5),
  best('Best', 9);

  const SevenZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень сжатия: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static SevenZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => SevenZipCompression.normal);
}
