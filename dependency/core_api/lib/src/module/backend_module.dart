import 'package:fc_api/fc_api.dart';

import '../tree/operation_kind.dart';
import '../tree/provider_registry.dart';
import '../tree/tree_provider.dart';

/// Ядровая половина модуля: то, что живёт там, где источники.
///
/// Экрана у этой стороны нет, и объявить здесь окно, команду или вид
/// невозможно — таких методов у [BackendRegistry] попросту не существует.
/// Модуль, которому нужно и то и другое, реализует **тем же классом** ещё и
/// `FcFrontendModule`: модуль — одна вещь, у которой две половины, а не две
/// вещи с общим именем (`docs/modules.md`).
abstract interface class FcBackendModule implements FcModule {
  /// Объявление того, что модуль даёт ядру.
  ///
  /// Зовётся один раз при сборке ядра. Здесь только объявления: никакой
  /// работы, никаких обращений к другим службам — их ещё нет. Работа, которую
  /// нужно сделать при запуске, делается в самом источнике.
  void installBackend(BackendRegistry registry);
}

/// Куда ядровая половина модуля складывает то, что предлагает.
///
/// Только запись: реестр объявлений существует ровно на время сборки. Читать
/// зависимости здесь нельзя — их ещё нет; для этого фабрикам приходит
/// [FcServices].
abstract interface class BackendRegistry {
  /// Службы ядра.
  ///
  /// Обращаться к ним можно **только из фабрик**: во время
  /// [FcBackendModule.installBackend] их ещё нет, а к моменту, когда фабрику
  /// позовут, — уже есть.
  FcServices get services;

  /// Раздел настроек этого модуля — под его же именем.
  ///
  /// Тот же раздел, что и у экранной половины: имя одно, а файл настроек
  /// принадлежит ядру.
  SettingsScope get settings;

  /// Корневой источник дерева — тот, с которого начинается любой путь.
  ///
  /// Ровно один на приложение: второй — ошибка сборки, а не молчаливая замена.
  void rootProvider(TreeProvider Function(FcServices services) factory);

  /// Вложенный источник: схема пути и расширения, которыми он открывается.
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}});

  /// Источник, открываемый по адресу: `ssh://user@host/srv`.
  ///
  /// В отличие от вложенного, такому не над чем монтироваться — он сам себе
  /// корень, и панель встаёт на него целиком.
  void addressProvider(String scheme, AddressFactory factory);

  /// Длительная работа, которую умеет этот модуль: упаковка, распаковка,
  /// проверка.
  ///
  /// Работа живёт **здесь**, где источники, а зовут её с той стороны заявкой
  /// (`OperationSpec`) — по имени [kind] и с доводами значениями. Команда при
  /// этом остаётся мелким мутатором: собрать заявку и отправить
  /// (`docs/spec/client-server.md`, §5.4).
  void operation(String kind, OperationFactory factory);

  /// Служба для ядра и других модулей: разрешается по типу через [FcServices].
  void service<T extends Object>(T Function(FcServices services) factory);
}
