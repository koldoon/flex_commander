import 'package:dicom/dicom.dart';
import 'package:fc_api/fc_api.dart';

/// Вложенный источник, объявленный модулем.
class ProviderRegistration {
  const ProviderRegistration(this.scheme, this.factory, this.extensions);

  final String scheme;
  final ProviderFactory factory;
  final Set<String> extensions;
}

/// Источник по адресу, объявленный модулем.
class AddressRegistration {
  const AddressRegistration(this.scheme, this.factory);

  final String scheme;
  final AddressFactory factory;
}

/// Службы приложения, доступные фабрикам.
///
/// Ссылку на них модуль получает во время сборки, когда контейнера ещё нет, —
/// и это нормально: обращаются к службам только из фабрик, а те зовутся уже
/// после сборки.
class LazyServices implements FcServices {
  DI? _container;

  /// Только для сборки: связывает службы с готовым контейнером.
  void bindTo(DI container) => _container = container;

  DI get _di {
    final container = _container;
    if (container == null) {
      throw StateError('Службы ещё не собраны: обращаться к ним можно только из фабрик');
    }
    return container;
  }

  @override
  T resolve<T>() => _di.get<T>();

  @override
  List<T> resolveAll<T>() {
    try {
      return _di.getAll<T>();
    } on Exception {
      // Ни одной реализации: для «сколько есть» это не ошибка.
      return [];
    }
  }
}

/// Всё, что модули предложили приложению.
///
/// Регистратор ([FcRegistry]) только собирает объявления; что с ними делать,
/// решает сборка. Поэтому здесь нет ни одного действия — только списки.
class Registrations implements FcRegistry {
  Registrations(this.services);

  @override
  final LazyServices services;

  /// Модули в порядке установки.
  final List<FcModule> modules = [];

  TreeProvider Function(FcServices services)? rootProviderFactory;

  /// Кто объявил корневой источник: имя нужно для внятной ошибки о втором.
  String? _rootProviderOwner;

  final List<ProviderRegistration> providers = [];
  final List<AddressRegistration> addresses = [];
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

  /// Виды содержимого панели: имя вида → чем рисовать.
  final Map<String, PanelViewportBuilder> viewports = {};

  /// Виды состояний: тип, на который объявлен, → сам вид.
  final Map<Type, StateView> views = {};

  /// Связывание службы с контейнером: тип известен только в момент объявления,
  /// поэтому он захватывается замыканием.
  final Map<Type, void Function(DI container)> serviceBindings = {};

  String? _current;

  /// Настройки приложения, когда их прочитают. До этого раздел модуля просить
  /// не у кого — и это не ошибка сборки, а ошибка того, кто спросил слишком рано.
  AppSettings? settingsSource;

  /// Устанавливает модули по порядку: порядок задаёт приоритет привязок.
  ///
  /// Модуль с уже занятым идентификатором пропускается. Список модулей
  /// складывается из нескольких мест — приложение, тест, вложенный набор, — и
  /// один и тот же модуль легко указать дважды; повторная установка удвоила бы
  /// его привязки, а с ними и подписи клавиш в справке.
  void installAll(Iterable<FcModule> list) {
    for (final module in list) {
      if (modules.any((installed) => installed.id == module.id)) {
        continue;
      }
      _current = module.id;
      modules.add(module);
      module.install(this);
    }
    _current = null;
  }

  /// Раздел настроек **того модуля, который сейчас объявляется**.
  ///
  /// Спрашивать его можно только из `install`, и это не придирка: имя раздела
  /// известно ровно до тех пор, пока идёт установка. Взятый позже — из фабрики
  /// команды, из замыкания — он достался бы последнему установленному модулю,
  /// и настройки уехали бы в чужой раздел молча. Так и случилось: терминал
  /// писал в раздел редактора, а обнаружилось это по чужим ключам в файле.
  ///
  /// Правильно — забрать область один раз и держать её:
  ///
  /// ```dart
  /// final settings = registry.settings;                       // в install
  /// registry.command((context) => MyCommand(settings.section(MySettings.new)));
  /// ```
  @override
  SettingsScope get settings {
    final namespace = _current;
    if (namespace == null) {
      throw StateError(
        'Раздел настроек спрашивают вне install: чей он — уже неизвестно. '
        'Заберите его в install («final settings = registry.settings») и держите.',
      );
    }
    return _LazyScope(this, namespace);
  }

  /// Кто устанавливался последним: реестр отдают модулю целиком, и он

  @override
  void rootProvider(TreeProvider Function(FcServices services) factory) {
    final owner = _rootProviderOwner;
    if (owner != null) {
      throw StateError('Корневой источник уже объявлен модулем $owner, второй объявляет $_current');
    }
    _rootProviderOwner = _current;
    rootProviderFactory = factory;
  }

  @override
  void provider(String scheme, ProviderFactory factory, {Set<String> extensions = const {}}) {
    providers.add(ProviderRegistration(scheme, factory, extensions));
  }

  @override
  void addressProvider(String scheme, AddressFactory factory) {
    addresses.add(AddressRegistration(scheme, factory));
  }

  @override
  void command(FcCommandFactory factory) {
    commands.add(factory);
    commandOwners.add(_ownerTitle);
  }

  /// Чьё сейчас объявление — названием, а не идентификатором: справке нужно
  /// человеческое имя, а `fc.file_ops` таковым не является.
  String get _ownerTitle {
    final id = _current;
    if (id == null) {
      return '';
    }
    return modules.firstWhere((module) => module.id == id).title;
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
  void service<T extends Object>(T Function(FcServices services) factory) {
    serviceBindings[T] = (container) => container.bind<T>(to: (c) => factory(services));
  }
}

/// Раздел настроек модуля, который добирается до них позже.
///
/// Модуль объявляет себя раньше, чем настройки прочитаны с диска: раздел он
/// получает сразу, а содержимое — когда оно появится.
class _LazyScope implements SettingsScope {
  const _LazyScope(this._registrations, this._namespace);

  final Registrations _registrations;
  final String _namespace;

  SettingsScope get _scope {
    final settings = _registrations.settingsSource;
    if (settings == null) {
      throw StateError('Настройки ещё не прочитаны: раздел модуля доступен из команд, а не из install');
    }
    return settings.modules.scope(_namespace);
  }

  @override
  T section<T extends Serializable>(T Function() create) => _scope.section(create);

  @override
  void save() => _scope.save();
}
