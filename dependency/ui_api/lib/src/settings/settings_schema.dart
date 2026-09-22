import 'dart:async';

import 'package:flutter/painting.dart';

import '../theme/color_text.dart';

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
  const SettingsField(this.id, {required this.title, this.description = '', this.note = '', this.keywords = const {}});

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

  /// Слова, которыми это ищут, но которых в подписи нет: `dark` у смены темы,
  /// `gzip` у упаковки.
  ///
  /// Без них команду «Switch theme» в окне клавиш было не найти ни одним из тех
  /// слов, которыми её ищут в палитре, — а искали её именно так
  /// (`docs/spec/key-bindings.md`, §8).
  final Set<String> keywords;

  /// Стоит ли сейчас умолчание.
  ///
  /// По этому окно решает, помечать ли настройку тронутой и предлагать ли
  /// вернуть умолчание. Спрашивается у поля, а не считается снаружи: значение
  /// у каждого вида своего типа, и сравнивать их одним способом нечем.
  bool get isDefault;

  /// Вернуть умолчание — и записать, как при обычной правке.
  void resetToDefault();

  /// Что в поле стоит сейчас; null — значения у поля нет вовсе.
  ///
  /// Этим набор и собирается: что в него входит, решает схема, а не список
  /// полей руками (`docs/spec/settings-presets.md`, §3). Значения у кнопки нет,
  /// а клавиши едут своим списком.
  Object? get value;

  /// Поставить значение, пришедшее набором.
  ///
  /// Чужое или испорченное — молча мимо: набор мог прийти из другого выпуска,
  /// и падать на нём незачем.
  void apply(Object? value);

  /// Флаг.
  static SettingsFlag flag(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required bool defaultValue,
    required bool Function() read,
    required void Function(bool value) write,
    SettingsAction? action,
  }) => SettingsFlag(
    id,
    title: title,
    description: description,
    note: note,
    defaultValue: defaultValue,
    read: read,
    write: write,
    action: action,
  );

  /// Целое число с пределами.
  static SettingsNumber integer(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required int min,
    required int max,
    String unit = '',
    required int defaultValue,
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
    defaultValue: defaultValue,
    read: read,
    write: write,
  );

  /// Дробное число с пределами.
  ///
  /// Рядом с [integer], а не признаком у него: у целого и дробного разный
  /// разбор набранного и разные пределы, а поле, которое иногда целое,
  /// пришлось бы спрашивать «а сейчас ты какое». Так правятся метрики
  /// оформления — все они `double`, и среди них есть доли
  /// (`docs/spec/theme-editor.md`, §4).
  static SettingsDecimal decimal(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required double min,
    required double max,
    String unit = '',
    required double defaultValue,
    required double Function() read,
    required void Function(double value) write,
  }) => SettingsDecimal(
    id,
    title: title,
    description: description,
    note: note,
    min: min,
    max: max,
    unit: unit,
    defaultValue: defaultValue,
    read: read,
    write: write,
  );

  /// Цвет: образец, поле `#AARRGGBB` и палитра за образцом.
  static SettingsColor color(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required Color defaultValue,
    required Color Function() read,
    required void Function(Color value) write,
    List<Color> palette = const [],
  }) => SettingsColor(
    id,
    title: title,
    description: description,
    note: note,
    defaultValue: defaultValue,
    read: read,
    write: write,
    palette: palette,
  );

  /// Строка.
  static SettingsText text(
    String id, {
    required String title,
    String description = '',
    String note = '',
    String hint = '',
    String defaultValue = '',
    required String Function() read,
    required void Function(String value) write,
  }) => SettingsText(
    id,
    title: title,
    description: description,
    note: note,
    hint: hint,
    defaultValue: defaultValue,
    read: read,
    write: write,
  );

  /// Список строк: строка на значение, у каждой «×», внизу «Add».
  ///
  /// Так стоит то, чего заранее не перечислить и чего бывает сколько угодно:
  /// словарь составных расширений. Строкой через точку с запятой это же
  /// правилось вслепую — чтобы убрать одно значение, надо было не промахнуться
  /// мимо разделителя (`docs/spec/settings-editor.md`, §8).
  static SettingsList list(
    String id, {
    required String title,
    String description = '',
    String note = '',
    String hint = '',
    List<String> defaultValue = const [],
    required List<String> Function() read,
    required void Function(List<String> value) write,
  }) => SettingsList(
    id,
    title: title,
    description: description,
    note: note,
    hint: hint,
    defaultValue: defaultValue,
    read: read,
    write: write,
  );

  /// Выбор из готового списка.
  static SettingsChoice choice(
    String id, {
    required String title,
    String description = '',
    String note = '',
    required Map<String, String> options,
    required String defaultValue,
    required String Function() read,
    required void Function(String value) write,
    List<SettingsAction> actions = const [],
  }) => SettingsChoice(
    id,
    title: title,
    description: description,
    note: note,
    options: options,
    defaultValue: defaultValue,
    read: read,
    write: write,
    actions: actions,
  );

  /// Кнопка: поле без значения.
  ///
  /// Так в настройках стоит то, что не выбирают, а **делают**: «Keymap»
  /// открывает своё окно (`docs/spec/key-bindings.md`, §7). Отдельным видом, а
  /// не приставкой к флажку ([SettingsFlag.action]): приставка уточняет
  /// настройку, а этой кнопке уточнять нечего — настройки у неё нет.
  static SettingsButton button(
    String id, {
    required String title,
    required String label,
    required FutureOr<void> Function()? run,
    String description = '',
    String note = '',
  }) => SettingsButton(id, title: title, description: description, note: note, label: label, run: run);

  /// Клавиша команды: на кнопке написано, чем команду вызывают сейчас.
  static SettingsKeys keys(
    String id, {
    required String title,
    required String Function() read,
    required String defaultKeys,
    required Future<void> Function() edit,
    required void Function() reset,
    String description = '',
    Set<String> keywords = const {},
  }) => SettingsKeys(
    id,
    title: title,
    description: description,
    keywords: keywords,
    read: read,
    defaultKeys: defaultKeys,
    edit: edit,
    reset: reset,
  );
}

/// Клавиша команды: показывается кнопкой, правится в своём окошке
/// (`docs/spec/key-bindings.md`, §8).
class SettingsKeys extends SettingsField {
  const SettingsKeys(
    super.id, {
    required super.title,
    required this.read,
    required this.defaultKeys,
    required this.edit,
    required this.reset,
    super.description,
    super.keywords,
  });

  /// Чем команду вызывают сейчас; пусто — ничем.
  ///
  /// Замыканием, а не строкой: форма строит схему один раз, а клавиша меняется,
  /// пока окно открыто, — записанное строкой так и осталось бы прежним.
  final String Function() read;

  /// Чем её вызывают по умолчанию; пусто — модуль клавиши не давал.
  final String defaultKeys;

  /// Открыть окошко записи и дождаться, пока его закроют.
  ///
  /// Ждать нужно форме: после правки ей перерисоваться, иначе на кнопке
  /// осталась бы прежняя клавиша.
  final Future<void> Function() edit;

  /// Забыть переназначения этой команды.
  final void Function() reset;

  @override
  bool get isDefault => read() == defaultKeys;

  @override
  void resetToDefault() => reset();

  /// Клавиши в набор попадают **своим списком**, а не значением поля: у
  /// привязки составной ключ, и строкой она была бы склейкой, которую пришлось
  /// бы разбирать обратно (`docs/spec/settings-presets.md`, §3).
  @override
  Object? get value => null;

  @override
  void apply(Object? value) {}
}

/// Поле, у которого нет значения: только кнопка.
class SettingsButton extends SettingsField {
  const SettingsButton(
    super.id, {
    required super.title,
    required this.label,
    required this.run,
    super.description,
    super.note,
  });

  /// Подпись кнопки.
  final String label;

  /// Что сделать по нажатию; null — делать нечего, и кнопка приглушена.
  ///
  /// Приглушена, а не спрятана: пропавшая кнопка означала бы, что действия нет
  /// вовсе, — а оно есть, просто сейчас неприменимо.
  ///
  /// Ответ ждут: кнопка, поднявшая окно, возвращается **тут же**, а сделанное
  /// в том окне случится потом — и пересобирать разделы надо после него, а не
  /// до (`docs/spec/settings-presets.md`, §6).
  final FutureOr<void> Function()? run;

  /// Тронуть её нечем: значения нет, а значит нет и умолчания, от которого
  /// можно отойти.
  @override
  bool get isDefault => true;

  @override
  void resetToDefault() {}

  @override
  Object? get value => null;

  @override
  void apply(Object? value) {}
}

class SettingsFlag extends SettingsField {
  const SettingsFlag(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.defaultValue,
    required this.read,
    required this.write,
    this.action,
  });

  /// Что стоит, пока не выбрали своего.
  final bool defaultValue;

  final bool Function() read;
  final void Function(bool value) write;

  /// Кнопка в той же строке; null — только флажок.
  ///
  /// Приставкой к флажку, а не отдельным полем: это одно дело, сказанное двумя
  /// способами — «делать самому» и «вот сейчас сделай». Так стоит «Check now»
  /// рядом с «проверять обновления» (`docs/spec/self-update.md`, §8).
  final SettingsAction? action;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  @override
  Object? get value => read();

  @override
  void apply(Object? value) {
    if (value is bool) {
      write(value);
    }
  }
}

/// Кнопка-приставка у поля настройки.
///
/// Значения у неё нет — значит и в сверке «у каждого поля схемы есть ключ в
/// разделе» ей делать нечего: сверять нечего.
class SettingsAction {
  const SettingsAction({required this.label, required this.run});

  /// Подпись кнопки.
  final String label;

  /// Что сделать по нажатию; null — делать нечего, и кнопка приглушена.
  ///
  /// Живой она остаётся независимо от самого поля: выключенная проверка по
  /// расписанию не значит, что нельзя проверить руками.
  ///
  /// Ответ ждут — как у [SettingsButton.run]: кнопка, поднявшая окно,
  /// возвращается тут же, а сделанное в том окне случится потом.
  final FutureOr<void> Function()? run;
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
    required this.defaultValue,
    required this.read,
    required this.write,
  });

  final int min;
  final int max;

  /// Что стоит, пока не выбрали своего.
  final int defaultValue;

  /// Единица измерения — подпись справа от поля: `bytes`, `lines`.
  final String unit;

  final int Function() read;
  final void Function(int value) write;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  /// Приводит набранное к допустимому; null — это не число вовсе.
  int? parse(String value) {
    return int.tryParse(value.trim())?.clamp(min, max);
  }

  @override
  Object? get value => read();

  @override
  void apply(Object? value) {
    // С поправкой на пределы: набор мог прийти оттуда, где они были другими.
    if (value is int) {
      write(value.clamp(min, max));
    }
  }
}

/// Дробное число с пределами.
///
/// Отдельный вид, а не признак у [SettingsNumber]: «ширина окна 0.75» в целом
/// поле невыразима, а поле, которое иногда целое, каждому читающему пришлось бы
/// спрашивать, какое оно сейчас (`docs/spec/theme-editor.md`, §4).
class SettingsDecimal extends SettingsField {
  const SettingsDecimal(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.min,
    required this.max,
    this.unit = '',
    required this.defaultValue,
    required this.read,
    required this.write,
  });

  final double min;
  final double max;

  /// Что стоит, пока не выбрали своего.
  final double defaultValue;

  /// Единица измерения — подпись справа от поля: `px`, `pt`.
  final String unit;

  final double Function() read;
  final void Function(double value) write;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  /// Приводит набранное к допустимому; null — это не число вовсе.
  ///
  /// Запятая считается точкой: на русской раскладке дробное набирают через
  /// неё, и отказ разобрать «1,5» выглядел бы поломкой поля.
  double? parse(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    return parsed == null || !parsed.isFinite ? null : parsed.clamp(min, max);
  }

  @override
  Object? get value => read();

  @override
  void apply(Object? value) {
    // Целое тоже годится: в json `22.0` сохраняется и читается обратно как
    // `22`, и отказ его принять терял бы каждое круглое значение.
    if (value is num) {
      write(value.toDouble().clamp(min, max));
    }
  }
}

/// Цвет: образец, поле `#AARRGGBB` и палитра за образцом.
///
/// Значение ходит [Color], а не числом: цвет тем и правят — образцом рядом с
/// полем, — а число пришлось бы разбирать обратно в каждом, кто такое поле
/// объявит.
class SettingsColor extends SettingsField {
  const SettingsColor(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.defaultValue,
    required this.read,
    required this.write,
    this.palette = const [],
  });

  /// Что стоит, пока не выбрали своего.
  final Color defaultValue;

  final Color Function() read;
  final void Function(Color value) write;

  /// Что предложить за образцом; пусто — предлагать нечего, и образец не
  /// нажимается.
  ///
  /// Список приносит тот, кто поле объявил: цвета, уже стоящие в теме,
  /// приложение знает, а поле — нет (`docs/spec/theme-editor.md`, §4).
  final List<Color> palette;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  /// Строкой, а не числом: в файле настроек цвет должен читаться глазами.
  @override
  Object? get value => formatColor(read());

  @override
  void apply(Object? value) {
    if (value is String) {
      if (parseColor(value) case final color?) {
        write(color);
      }
    }
  }
}

class SettingsText extends SettingsField {
  const SettingsText(
    super.id, {
    required super.title,
    super.description,
    super.note,
    this.hint = '',
    this.defaultValue = '',
    required this.read,
    required this.write,
  });

  /// Что показать в пустом поле — обычно объяснение умолчания.
  final String hint;

  /// Что стоит, пока не выбрали своего; обычно пусто — и подсказка объясняет,
  /// что будет в этом случае.
  final String defaultValue;

  final String Function() read;
  final void Function(String value) write;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  @override
  Object? get value => read();

  @override
  void apply(Object? value) {
    if (value is String) {
      write(value);
    }
  }
}

/// Список строк: значение на строку.
///
/// Значения тут **однородны** — расширения, маски, имена, — и потому список
/// хранится списком с самого начала: разбирать строку через разделитель
/// значило бы договариваться о разделителе с каждым, кто такое поле объявит.
class SettingsList extends SettingsField {
  const SettingsList(
    super.id, {
    required super.title,
    super.description,
    super.note,
    this.hint = '',
    this.defaultValue = const [],
    required this.read,
    required this.write,
  });

  /// Что показать в пустой строке — образец значения, а не объяснение поля:
  /// объяснение стоит выше, над всем списком.
  final String hint;

  /// Что стоит, пока не выбрали своего; обычно пусто.
  final List<String> defaultValue;

  final List<String> Function() read;

  /// Записать список целиком.
  ///
  /// Целиком, а не «добавить» и «убрать» по одному: правка строки — это тоже
  /// изменение списка, и трёх способов сказать одно и то же поле не заслужило.
  final void Function(List<String> value) write;

  @override
  bool get isDefault => _same(read(), defaultValue);

  @override
  void resetToDefault() => write([...defaultValue]);

  /// Копией, а не самим списком: набор переживёт своё поле, а список у раздела
  /// изменяемый — тот же объект в наборе менялся бы вслед за настройкой.
  @override
  Object? get value => [...read()];

  @override
  void apply(Object? value) {
    // Только список строк: чужое молча мимо — набор мог прийти из другого
    // выпуска, где это поле было строкой.
    if (value is List && value.every((item) => item is String)) {
      write([for (final item in value) item as String]);
    }
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class SettingsChoice extends SettingsField {
  const SettingsChoice(
    super.id, {
    required super.title,
    super.description,
    super.note,
    required this.options,
    required this.defaultValue,
    required this.read,
    required this.write,
    this.actions = const [],
  });

  /// Кнопки под списком — то, что делают с выбранным.
  ///
  /// Рядом с ним, а не отдельными настройками: «сложить», «обновить»,
  /// «удалить» и «выгрузить» относятся к выбору, стоящему выше, и блок на
  /// каждую превращал бы раздел в простыню
  /// (`docs/spec/settings-presets.md`, §6).
  final List<SettingsAction> actions;

  /// Значение → подпись.
  final Map<String, String> options;

  /// Что стоит, пока не выбрали своего.
  final String defaultValue;

  final String Function() read;
  final void Function(String value) write;

  @override
  bool get isDefault => read() == defaultValue;

  @override
  void resetToDefault() => write(defaultValue);

  @override
  Object? get value => read();

  @override
  void apply(Object? value) {
    // Только то, что есть в списке: вариант мог пропасть вместе с выключенным
    // модулем, и ставить его значило бы выбрать несуществующее.
    if (value is String && options.containsKey(value)) {
      write(value);
    }
  }
}

/// Раздел окна настроек: чьи это поля и как их получить.
///
/// Схема — **фабрика**, а не готовое значение: во время объявления модулей
/// настройки ещё не прочитаны с диска, и строить её тогда нечем.
class SettingsPage {
  const SettingsPage({required this.title, required this.build, this.id = '', this.inPreset = true, this.priority = 0});

  /// Название модуля — оно же заголовок раздела, как в справке.
  ///
  /// Не всегда: раздел вправе назваться сам, если модуль отвечает не только за
  /// себя (`registry.settingsSchema(title: 'Presets')`).
  final String title;

  /// Идентификатор модуля (`fc.terminal`), а не заголовок.
  ///
  /// Им раздел назван в наборе выбора: заголовок переводится и меняется от
  /// выпуска к выпуску, а идентификатор — нет
  /// (`docs/spec/settings-presets.md`, §2).
  final String id;

  /// Насколько высоко раздел стоит: **больше — выше**; 0 — на своём месте.
  ///
  /// Порядок разделов — это порядок модулей, и менять его без причины незачем.
  /// Но причина бывает: наборы выбора не про свой модуль, а про все сразу, и
  /// после прочих читались бы как приписка к последнему из них. Объявлены они
  /// оболочкой, а встать обязаны первыми — тогда как первым устанавливается не
  /// она (`docs/spec/settings-presets.md`, §6).
  ///
  /// Числом, а не признаком «сверху»: разделов, просящихся вперёд, со временем
  /// станет больше одного, и порядок между ними тоже придётся называть.
  /// Равные стоят в порядке объявления.
  final int priority;

  /// Входят ли поля раздела в набор выбора.
  ///
  /// Не входят у самих наборов: набор, помнящий, какой набор выбран, — это
  /// петля.
  final bool inPreset;

  final SettingsSchema Function() build;
}

/// Все разделы настроек, в порядке объявления модулей.
///
/// Служба ядра: её спрашивает окно настроек. Модуль о ней не знает — он только
/// объявляет свою схему.
abstract interface class SettingsCatalog {
  List<SettingsPage> get pages;
}
