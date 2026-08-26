/// Из чего состоит раздел настроек — то, что модуль рассказывает о себе, чтобы
/// ядро нарисовало окно.
///
/// Модуль не рисует ничего: он перечисляет поля, а как они выглядят и как
/// ходит по ним `Tab`, решает одно место на всё приложение.
///
/// **Перечисляет, а не отдаёт раздел целиком.** В разделе лежит и то, что
/// человек выбирает, и то, что приложение за ним запоминает: история команд,
/// геометрия окна, положение курсора. Второе в настройках показывать нельзя —
/// предложить его редактировать значит либо бессмыслицу, либо вред.
class SettingsSchema {
  const SettingsSchema(this.fields, {required this.save});

  final List<SettingsField> fields;

  /// Как попросить сохранить: обычно `settings.save` своего раздела.
  ///
  /// Зовётся после каждой правки — запись отложенная, подряд идущие изменения
  /// сливаются в одну.
  final void Function() save;
}

/// Одно поле.
///
/// Запечатанный тип: видов немного, и каждый рисуется по-своему — «про флаг
/// можно соврать, про отсутствие метода нельзя». Значение поле берёт и кладёт
/// **замыканиями**, а не по имени ключа: замыкание работает с тем же
/// типизированным объектом, что и сам модуль, и ошибку в нём ловит компилятор.
sealed class SettingsField {
  const SettingsField(this.id, {required this.title, this.description = '', this.note = ''});

  /// Ключ в разделе настроек.
  ///
  /// Не для чтения значения — для сверки: тест проверяет, что у каждого поля
  /// схемы есть такой ключ в `toMap` раздела. Схема, разошедшаяся с данными,
  /// иначе разойдётся молча.
  final String id;

  /// Подпись поля.
  final String title;

  /// Что это значит — строкой под подписью; пусто — объяснять нечего.
  final String description;

  /// Оговорка о том, когда изменение подействует: «со следующего запуска
  /// оболочки». Пусто — подействует сразу.
  final String note;

  /// Флаг.
  static SettingsFlag flag(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required bool Function() read,
    required void Function(bool value) write,
  }) => SettingsFlag(id, title: title, description: description, note: note, read: read, write: write);

  /// Целое число с пределами.
  static SettingsNumber integer(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required int min,
    required int max,
    String unit = '',
    required int Function() read,
    required void Function(int value) write,
  }) => SettingsNumber(
    id,
    title: title,
    description: description,
    note: note,
    min: min,
    max: max,
    unit: unit,
    read: read,
    write: write,
  );

  /// Строка.
  static SettingsText text(
    String id, {
    required String title,
    String description = '',
    String note = '',
    String hint = '',
    required String Function() read,
    required void Function(String value) write,
  }) => SettingsText(id, title: title, description: description, note: note, hint: hint, read: read, write: write);

  /// Выбор из готового списка.
  static SettingsChoice choice(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required Map<String, String> options,
    required String Function() read,
    required void Function(String value) write,
  }) => SettingsChoice(
    id,
    title: title,
    description: description,
    note: note,
    options: options,
    read: read,
    write: write,
  );
}

class SettingsFlag extends SettingsField {
  const SettingsFlag(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.read,
    required this.write,
  });

  final bool Function() read;
  final void Function(bool value) write;
}

class SettingsNumber extends SettingsField {
  const SettingsNumber(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.min,
    required this.max,
    this.unit = '',
    required this.read,
    required this.write,
  });

  final int min;
  final int max;

  /// Единица измерения — подпись справа от поля: `bytes`, `lines`.
  final String unit;

  final int Function() read;
  final void Function(int value) write;

  /// Приводит набранное к допустимому; null — это не число вовсе.
  int? parse(String value) {
    return int.tryParse(value.trim())?.clamp(min, max);
  }
}

class SettingsText extends SettingsField {
  const SettingsText(
    super.id, {
    required super.title,
    super.description,
    super.note,
    this.hint = '',
    required this.read,
    required this.write,
  });

  /// Что показать в пустом поле — обычно объяснение умолчания.
  final String hint;

  final String Function() read;
  final void Function(String value) write;
}

class SettingsChoice extends SettingsField {
  const SettingsChoice(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.options,
    required this.read,
    required this.write,
  });

  /// Значение → подпись.
  final Map<String, String> options;

  final String Function() read;
  final void Function(String value) write;
}

/// Раздел окна настроек: чьи это поля и как их получить.
///
/// Схема — **фабрика**, а не готовое значение: во время объявления модулей
/// настройки ещё не прочитаны с диска, и строить её тогда нечем.
class SettingsPage {
  const SettingsPage({required this.title, required this.build});

  /// Название модуля — оно же заголовок раздела, как в справке.
  final String title;

  final SettingsSchema Function() build;
}

/// Все разделы настроек, в порядке объявления модулей.
///
/// Служба ядра: её спрашивает окно настроек. Модуль о ней не знает — он только
/// объявляет свою схему.
abstract interface class SettingsCatalog {
  List<SettingsPage> get pages;
}
