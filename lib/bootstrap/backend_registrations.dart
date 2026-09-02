import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'registrations.dart';

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

/// Всё, что ядровые половины модулей предложили ядру.
///
/// Реестр только собирает объявления; что с ними делать, решает сборка.
/// Поэтому здесь нет ни одного действия — только списки.
class BackendRegistrations extends ModuleRegistrations<FcBackendModule> implements BackendRegistry {
  BackendRegistrations(super.services);

  TreeProvider Function(FcServices services)? rootProviderFactory;

  /// Кто объявил корневой источник: имя нужно для внятной ошибки о втором.
  String? _rootProviderOwner;

  final List<ProviderRegistration> providers = [];
  final List<AddressRegistration> addresses = [];

  @override
  void install(FcBackendModule module) => module.installBackend(this);

  @override
  void rootProvider(TreeProvider Function(FcServices services) factory) {
    final owner = _rootProviderOwner;
    if (owner != null) {
      throw StateError('Корневой источник уже объявлен модулем $owner, второй объявляет $ownerTitle');
    }
    _rootProviderOwner = ownerTitle;
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
  void service<T extends Object>(T Function(FcServices services) factory) => bindService<T>(factory);
}
