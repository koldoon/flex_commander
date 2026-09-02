import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'registrations.dart';

/// Всё, что экранные половины модулей предложили интерфейсу.
///
/// Реестр только собирает объявления; что с ними делать, решает сборка.
/// Поэтому здесь нет ни одного действия — только списки.
class FrontendRegistrations extends ModuleRegistrations<FcFrontendModule> implements FrontendRegistry {
  FrontendRegistrations(super.services);

  final List<FcCommandFactory> commands = [];

  /// Название модуля, объявившего команду, — по тому же месту в списке, что и
  /// сама команда.
  ///
  /// Нужно справке: она показывает команды **по модулям**, и без этого
  /// пришлось бы гадать по идентификаторам. Список, а не карта: имени команды
  /// на момент объявления ещё нет — есть только фабрика.
  final List<String> commandOwners = [];
  final List<KeyBinding> bindings = [];
  final List<FcCommandFactory> startupCommands = [];
  final List<FcThemeSpec> themes = [];

  /// Разделы окна настроек — в порядке объявления модулей, с их же названиями.
  final List<SettingsPage> settingsPages = [];

  /// Виды содержимого панели: имя вида → чем рисовать.
  final Map<String, PanelViewportBuilder> viewports = {};

  /// Объявленные просмотрщики — в порядке объявления; по приоритету их
  /// расставит приложение.
  final List<ViewerSpec> viewers = [];

  /// Провайдеры сведений — фабриками: их зовут, когда приложение уже собрано,
  /// как и фабрики команд.
  final List<NodeInfoProvider Function(FcContext context)> nodeInfoFactories = [];

  /// Виды состояний: тип, на который объявлен, → сам вид.
  final Map<Type, StateView> views = {};

  @override
  void install(FcFrontendModule module) => module.installFrontend(this);

  @override
  void command(FcCommandFactory factory) {
    commands.add(factory);
    commandOwners.add(ownerTitle);
  }

  @override
  void settingsSchema(SettingsSchema Function() factory) {
    settingsPages.add(SettingsPage(title: ownerTitle, build: factory));
  }

  @override
  void binding(KeyBinding binding) => bindings.add(binding);

  @override
  void startup(FcCommandFactory factory) => startupCommands.add(factory);

  @override
  void theme(FcThemeSpec spec) => themes.add(spec);

  @override
  void viewport(String kind, PanelViewportBuilder builder) => viewports[kind] = builder;

  @override
  void viewer(ViewerSpec spec) {
    final taken = viewers.indexWhere((declared) => declared.id == spec.id);
    if (taken >= 0) {
      // Два просмотрщика под одним именем — это не выбор, а недосмотр: имя
      // уйдёт в настройки и в «открыть чем», и победа последнего сделала бы
      // показ зависящим от порядка модулей в списке.
      throw StateError('Просмотрщик «${spec.id}» уже объявлен');
    }
    viewers.add(spec);
  }

  @override
  void nodeInfo(NodeInfoProvider Function(FcContext context) factory) => nodeInfoFactories.add(factory);

  @override
  void view<S extends Object>(StateViewBuilder<S> builder) {
    final taken = views[S];
    if (taken != null) {
      // Тихая победа последнего означала бы, что вид зависит от порядка
      // модулей в списке, — а он там стоит ради приоритета привязок клавиш,
      // и трогать его ради картинки никто не станет.
      throw StateError('Вид для $S уже объявлен: два вида на один тип — это ошибка, а не выбор');
    }
    views[S] = StateView(
      stateType: S,
      matches: (state) => state is S,
      build: (context, state) => builder(context, state as S),
    );
  }

  @override
  void service<T extends Object>(T Function(FcServices services) factory) => bindService<T>(factory);
}
