import 'package:fc_api/fc_api.dart'
    show AddressFactory, FcThemeSpec, ProviderFactory, SettingsScope, StateViewBuilder, TreeProvider, ViewportState;
import 'package:flutter/foundation.dart';

import 'application.dart';
import 'command.dart';

/// Как создать команду. Зависимости подставляет контейнер.
///
/// Экземпляр создаётся один раз, при установке: команда — прототип и состояния
/// прогона не держит.
typedef FcCommandFactory = AppCommand Function(FcContext context);

/// Возможность приложения, собранная в отдельном пакете.
///
/// Ядро знает модули только списком. Выключение модуля обязано убирать
/// возможность, а не ломать сборку.
abstract interface class FcModule {
  String get id;

  String get title;

  /// Объявить всё, что модуль приносит.
  ///
  /// Только объявить: ни разрешать зависимости, ни читать настройки, ни делать
  /// работу здесь нельзя — на этой фазе ничего ещё нет. Всё, что нужно сделать
  /// на запуске, делается стартовой командой.
  void install(FcRegistry registry);
}

/// Чем модуль объявляет свои возможности.
///
/// Узкий типизированный фасад над контейнером: внутри те же биндинги, но
/// список `install` читается как перечень того, что модуль приносит, а не как
/// набор безымянных регистраций.
abstract interface class FcRegistry {
  /// Службы — для фабрик. Приложения здесь нет намеренно: фабрика службы не
  /// должна до него дотягиваться, и это проверяет компилятор.
  FcServices get services;

  /// Раздел настроек этого модуля.
  SettingsScope get settings;

  /// Источник, с которого начинается общее дерево. Ровно один на приложение.
  void rootProvider(TreeProvider Function(FcServices services) factory);

  /// Источник, монтирующийся над узлом: архив.
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}});

  /// Источник со своим корнем, открываемый по адресу: `ssh://user@host/srv`.
  void addressProvider(String scheme, AddressFactory factory);

  void command(FcCommandFactory factory);

  void binding(KeyBinding binding);

  /// Команда, выполняемая на запуске. Её падение не должно ронять запуск.
  void startup(FcCommandFactory factory);

  void theme(FcThemeSpec spec);

  /// Чем рисовать состояние типа [S].
  ///
  /// Одним механизмом рисуются и содержимое областей ([ViewportState]), и окна
  /// заявок ([UserActionRequest]): и там, и там объект данных отдельно, вид
  /// отдельно, а связь между ними проверяет компилятор.
  ///
  /// Ключ — **точный тип**. Два вида на один тип — ошибка сборки, а не тихая
  /// победа последнего. Подтип своего вида не наследует: если он заведён, для
  /// него и регистрируют. Простой вопрос из кнопок вида не требует —
  /// `ChoiceRequest` рисует ядро, и пользоваться ей нужно как есть, а не
  /// наследоваться.
  void view<S extends Object>(StateViewBuilder<S> builder);

  /// Строки модуля для одного языка. Идентификатор строки начинается с
  /// идентификатора модуля.
  void strings(String locale, Map<String, String> table);

  void service<T extends Object>(T Function(FcServices services) factory);
}

/// Службы приложения.
abstract interface class FcServices {
  T resolve<T>();

  /// null — такой службы не установили.
  ///
  /// Нужен необязательным возможностям: перетаскивание (Ж2) приносит модуль,
  /// и панель обязана работать без него. Отсутствие модуля значит «нет
  /// перетаскивания», а не «панель не собралась».
  T? resolveOrNull<T>();

  List<T> resolveAll<T>();
}

/// То же плюс само приложение: его получают команды, но не фабрики служб.
abstract interface class FcContext implements FcServices {
  Application get app;
}

/// Строки интерфейса.
///
/// Свой реестр, без `intl` и кодогенерации: строки приносят модули, и знать
/// заранее их состав нельзя. Неизвестный язык или идентификатор откатывается
/// к английскому, а потом к самому идентификатору — пустое место в интерфейсе
/// хуже, чем невпопад переведённое слово.
///
/// [Listenable], потому что язык переключают на ходу: `AppCommand.label` —
/// геттер и вычисляется отсюда, поэтому нижний ряд кнопок и список команд
/// подписываются на строки и перерисовываются сами.
abstract interface class Strings implements Listenable {
  String get locale;

  String tr(String id, {Map<String, Object?> args = const {}});

  String plural(String id, int count);
}
