/// Упаковщик, объявленный модулем: чем и во что паковать.
///
/// Реестром, а не командой на каждый формат: место — свойство заявки, а не
/// формата, и палитра из четырёх строк, говорящих одно и то же, никому не
/// нужна (`docs/spec/archive-here.md`, §4).
class PackerSpec {
  const PackerSpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.extension,
    this.choice,
    this.nameOption = 'name',
    this.followLinksOption = 'followLinks',
  });

  /// Чем упаковщик зовётся в настройках и в окне: `zip`, `tar`, `7z`.
  final String id;

  /// Как формат называется человеку: «ZIP», «TAR», «7z».
  final String title;

  /// Имя работы ядра: `zip.pack`. Её объявляет тот же модуль.
  final String kind;

  /// Расширение по умолчанию — им дополняется имя, если человек не написал
  /// своего.
  final String extension;

  /// Свой довод формата: степень сжатия у zip, вид контейнера у tar.
  final PackerChoice? choice;

  /// Как работа зовёт имя архива и проход по ссылкам. У всех троих одинаково,
  /// но договор лучше записать, чем предполагать.
  final String nameOption;
  final String followLinksOption;
}

/// Выбор из нескольких значений — одна строка в окне упаковки.
///
/// Списком, а не произвольным виджетом: у всех нынешних упаковщиков свой довод
/// устроен одинаково — выбрать одно из нескольких. Появится формат, которому
/// этого мало, — тогда и заведём ему окно (`docs/spec/archive-here.md`, §4).
class PackerChoice {
  const PackerChoice({required this.option, required this.label, required this.values, required this.fallback});

  /// Как довод зовётся в заявке: `compression`, `format`.
  final String option;

  /// Подпись строки в окне: «Compression».
  final String label;

  final List<PackerValue> values;

  /// Что выбрано, пока не выбрали другого.
  final String fallback;
}

/// Одно значение довода: что уйдёт в заявку, как это зовут человеку и чем
/// кончается имя архива, если от значения зависит и оно.
class PackerValue {
  const PackerValue(this.value, this.title, {this.extension = ''});

  /// Что уйдёт в заявку: `best`, `gzip`.
  final String value;

  /// Как значение называется человеку: «Best», «tar.gz».
  final String title;

  /// Чем кончается имя архива при этом значении; пусто — расширение от
  /// значения не зависит (степень сжатия имени не меняет).
  ///
  /// Иначе выбор молча расходится с именем: `tar` без сжатия ложился в файл
  /// `.tar.gz` (`docs/spec/archive-here.md`, §8).
  final String extension;
}

/// Объявленные упаковщики — в порядке объявления модулей.
abstract interface class Packers {
  List<PackerSpec> get all;
}
