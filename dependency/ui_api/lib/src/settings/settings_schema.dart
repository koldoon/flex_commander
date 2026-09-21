import 'dart:async';

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
  const SettingsPage({
    required this.title,
    required this.build,
    this.id = '',
    this.inPreset = true,
    this.atTop = false,
  });

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

  /// Раздел стоит **впереди прочих**, а не на месте своего модуля.
  ///
  /// Оговорка, а не порядок объявления: разделы идут по модулям, а наборы
  /// выбора — не про свой модуль, а про все сразу, и после прочих читались бы
  /// как приписка к последнему из них. Объявлены они оболочкой, но встать
  /// обязаны первыми — а первым устанавливается не она
  /// (`docs/spec/settings-presets.md`, §6).
  final bool atTop;

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
