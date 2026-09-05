/// API интерфейса Flex Commander: то, против чего пишется экранная часть модуля.
///
/// Приложение и панели, команды с их реестром и клавишами, виды содержимого,
/// просмотрщики, оформление и службы, которым нужен экран. Источников здесь
/// нет: дерево живёт в ядре, а сюда приезжают значения
/// (`spec/client-server.md`, §3).
library;

// --- Приложение и панели ---
export 'src/app/application.dart';
export 'src/app/panel.dart';
export 'src/app/panel_viewport.dart';
export 'src/app/node_info.dart';
export 'src/app/content_types.dart';
export 'src/app/viewer_spec.dart';
export 'src/app/drag_and_drop.dart';
export 'src/app/views.dart';
export 'src/app/viewport.dart';
export 'src/app/errors.dart';
export 'src/app/toasts.dart';

// --- Действия и клавиши ---
export 'src/commands/app_command.dart';
export 'src/commands/async_run.dart';
export 'src/commands/command_registry.dart';
export 'src/commands/command_service.dart';
export 'src/commands/key_combination.dart';
export 'src/background/operations.dart';

// --- Модули ---
export 'src/module/frontend_module.dart';

// --- Настройки ---
export 'src/settings/settings_schema.dart';

// --- Оформление ---
export 'src/theme/app_colors.dart';
export 'src/theme/app_metrics.dart';
export 'src/theme/fc_fonts.dart';
export 'src/theme/fc_icons.dart';
export 'src/theme/theme_service.dart';

// --- Службы с экраном ---
export 'src/os/clipboard.dart';
export 'src/os/window_service.dart';
