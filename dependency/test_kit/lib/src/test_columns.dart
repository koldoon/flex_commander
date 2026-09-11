import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/backend_registrations.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/frontend_registrations.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flex_commander/core/column_sorting_registry.dart';
import 'package:flex_commander/state/column_registry.dart';

/// Колонки, объявленные ядровыми половинами модулей приложения.
///
/// Тем же списком, что и в настоящем запуске: сравнение колонки приносит
/// модуль, и проверка, собравшая панель без реестра, сортировала бы всё по
/// имени и этого бы не заметила (`docs/spec/column-registry.md`, §5).
ColumnSorting testColumnSorting() {
  return _sorting ??= () {
    final backend = BackendRegistrations(LazyServices())..installAll(backendModules());
    return ColumnSortingRegistry(const _TestServices(), backend.columns);
  }();
}

/// Объявления одни на весь прогон: установка модулей ради каждой панели —
/// работа на ровном месте, а объявления от прогона к прогону не меняются.
ColumnSorting? _sorting;

/// Колонки, объявленные экранными половинами модулей приложения.
///
/// Тем же списком, что и в настоящем запуске: без объявлений раскладка панели
/// выходит пустой, и таблица встаёт без единой колонки.
PanelColumns testPanelColumns() {
  return _shown ??= ColumnRegistry((FrontendRegistrations(LazyServices())..installAll(frontendModules())).columns);
}

PanelColumns? _shown;

/// Службы для сравнений: только то, что им и правда нужно.
///
/// Словаря составных расширений в проверке нет — сравнение по расширению берёт
/// обычное правило. Настоящий словарь собирается из настроек, и поднимать ради
/// него контейнер значило бы поднимать приложение.
class _TestServices implements FcServices {
  const _TestServices();

  @override
  T resolve<T>() {
    if (T == FileNaming) {
      return const ReferenceFileNaming() as T;
    }
    throw StateError('Служба $T проверке не подставлена');
  }

  @override
  List<T> resolveAll<T>() => const [];
}
