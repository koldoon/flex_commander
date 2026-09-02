import 'package:dicom/dicom.dart';
import 'package:fc_api/fc_api.dart';

/// Службы одной стороны, доступные фабрикам.
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

/// Общее у обоих сборщиков объявлений: список модулей, службы и настройки.
///
/// Сторон две, и каждая собирает своё (`docs/spec/client-server.md`, §8), но
/// правила установки у них одни: модули идут по порядку, повторный
/// идентификатор пропускается, раздел настроек принадлежит тому, кто сейчас
/// объявляется.
abstract class ModuleRegistrations<M extends FcModule> {
  ModuleRegistrations(this.services);

  /// Службы своей стороны.
  final LazyServices services;

  /// Модули этой стороны в порядке установки.
  final List<M> modules = [];

  /// Связывание службы с контейнером: тип известен только в момент
  /// объявления, поэтому он захватывается замыканием.
  final Map<Type, void Function(DI container)> serviceBindings = {};

  /// Настройки приложения, когда их прочитают. До этого раздел модуля просить
  /// не у кого — и это не ошибка сборки, а ошибка того, кто спросил слишком
  /// рано.
  AppSettings? settingsSource;

  String? _current;

  /// Устанавливает модули по порядку: порядок задаёт приоритет привязок.
  ///
  /// Модуль с уже занятым идентификатором пропускается. Список модулей
  /// складывается из нескольких мест — приложение, тест, вложенный набор, — и
  /// один и тот же модуль легко указать дважды; повторная установка удвоила бы
  /// его привязки, а с ними и подписи клавиш в справке.
  void installAll(Iterable<M> list) {
    for (final module in list) {
      if (modules.any((installed) => installed.id == module.id)) {
        continue;
      }
      _current = module.id;
      modules.add(module);
      install(module);
    }
    _current = null;
  }

  /// Чем именно установить модуль — своё у каждой стороны.
  void install(M module);

  /// Раздел настроек **того модуля, который сейчас объявляется**.
  ///
  /// Спрашивать его можно только из установки, и это не придирка: имя раздела
  /// известно ровно до тех пор, пока она идёт. Взятый позже — из фабрики
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
  SettingsScope get settings {
    final namespace = _current;
    if (namespace == null) {
      throw StateError(
        'Раздел настроек спрашивают вне установки: чей он — уже неизвестно. '
        'Заберите его в install («final settings = registry.settings») и держите.',
      );
    }
    return _LazyScope(this, namespace);
  }

  /// Чьё сейчас объявление — названием, а не идентификатором: справке нужно
  /// человеческое имя, а `fc.file_ops` таковым не является.
  String get ownerTitle {
    final id = _current;
    if (id == null) {
      return '';
    }
    return modules.firstWhere((module) => module.id == id).title;
  }

  void bindService<T extends Object>(T Function(FcServices services) factory) {
    serviceBindings[T] = (container) => container.bind<T>(to: (c) => factory(services));
  }
}

/// Раздел настроек модуля, который добирается до них позже.
///
/// Модуль объявляет себя раньше, чем настройки прочитаны: раздел он получает
/// сразу, а содержимое — когда оно появится.
class _LazyScope implements SettingsScope {
  const _LazyScope(this._registrations, this._namespace);

  final ModuleRegistrations _registrations;
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
