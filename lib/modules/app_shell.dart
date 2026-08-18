import 'package:fc_api/fc_api.dart';

/// Оболочка приложения: то, что есть у файлового менеджера всегда.
///
/// Пока это только движок файловых операций. Сюда же переедет всё, что
/// останется в ядре, когда команды разъедутся по модулям: содержимое панели
/// по умолчанию и общее место для фоновых работ.
class AppShell implements FcModule {
  const AppShell();

  @override
  String get id => 'fc.shell';

  @override
  String get title => 'Application shell';

  @override
  void install(FcRegistrar registrar) {
    // Движок один на приложение: состояния у него нет, а провайдеров узлы
    // приносят с собой — в том числе разных у источника и приёмника.
    registrar.service<TreeEditor>((services) => const TreeTransferEngine());
  }
}
