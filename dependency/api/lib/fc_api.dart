/// API Flex Commander: то, против чего пишутся модули.
///
/// Здесь только контракты и то, что из них следует: дерево узлов и провайдеры,
/// длительные операции, действия с их реестром, панели и приложение,
/// настройки, общие элементы интерфейса. Ни файловой системы, ни окна, ни
/// конкретных провайдеров — всё это живёт в модулях, а пакет остаётся тем, во
/// что они включаются.
///
/// `dart:io` в пакете нет вовсе: за этим следит `test/purity_test.dart`.
library;

// --- Приложение и панели ---
export 'src/app/application.dart';
export 'src/app/panel.dart';
export 'src/app/panel_selection.dart';
export 'src/app/panel_viewport.dart';
export 'src/app/views.dart';
export 'src/app/viewport.dart';
export 'src/app/errors.dart';
export 'src/app/toasts.dart';

// --- Дерево и провайдеры ---
export 'src/tree/file_attributes.dart';
export 'src/tree/file_type.dart';
export 'src/tree/fs_node.dart';
export 'src/tree/node_path.dart';
export 'src/tree/provider_lease.dart';
export 'src/tree/provider_registry.dart';
export 'src/tree/staging.dart';
export 'src/tree/transfer/local_copy_session.dart';
export 'src/tree/transfer/transfer_engine.dart';
export 'src/tree/tree_provider.dart';

// --- Длительные операции ---
export 'src/async/async_operation.dart';
export 'src/async/operation_request.dart';
export 'src/async/transfer_progress.dart';

// --- Действия и клавиши ---
export 'src/commands/app_command.dart';
export 'src/commands/async_command_base.dart';
export 'src/commands/command_registry.dart';
export 'src/commands/command_service.dart';
export 'src/commands/key_combination.dart';

// --- Фоновые работы ---
export 'src/background/task_status.dart';

// --- Модули ---
export 'src/module/fc_module.dart';

// --- Колонки, сортировка, настройки ---
export 'src/panel/column_spec.dart';
export 'src/panel/sort_spec.dart';
export 'src/serialization.dart';
export 'src/settings/app_settings.dart';
export 'src/settings/module_settings.dart';
export 'src/settings/window_geometry.dart';

// --- Оформление: роли, а не то, чем их рисуют ---
export 'src/theme/app_colors.dart';
export 'src/theme/app_metrics.dart';
export 'src/theme/fc_fonts.dart';
export 'src/theme/fc_icons.dart';
export 'src/theme/theme_service.dart';

// --- Служебное ---
export 'src/format/date_format.dart';
export 'src/format/duration_format.dart';
export 'src/format/size_format.dart';
export 'src/os/clipboard.dart';
export 'src/os/credentials.dart';
export 'src/os/process_runner.dart';
export 'src/os/system_opener.dart';
export 'src/os/window_service.dart';
export 'src/util/throttle.dart';
