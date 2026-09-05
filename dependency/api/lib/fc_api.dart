/// Общее обеим сторонам Flex Commander: то, что пересекает границу.
///
/// Приложение разделено на две стороны — ядро (`fc_core_api`) и интерфейс
/// (`fc_ui_api`), — и они друг друга не видят вовсе. Здесь лежит третье:
/// значения, которые ходят между ними, работы, форматы и типы настроек.
///
/// Правило простое: сюда попадает то, что нужно **обеим** сторонам. Узлам,
/// источникам и виджетам здесь места нет — они по разные стороны и знать друг
/// о друге не должны (`spec/client-server.md`, §3).
///
/// `dart:io` в пакете нет вовсе: за этим следит `test/purity_test.dart`.
library;

// --- Значения границы ---
export 'src/values/file_attributes.dart';
export 'src/values/file_type.dart';
export 'src/values/fs_error.dart';
export 'src/values/provider_capabilities.dart';

// --- Протокол границы ---
export 'src/protocol/content.dart';
export 'src/protocol/core_message.dart';
export 'src/protocol/entry_ref.dart';
export 'src/protocol/operation_spec.dart';
export 'src/protocol/file_entry.dart';
export 'src/protocol/panel_state.dart';
export 'src/protocol/source_info.dart';
export 'src/protocol/ui_settings.dart';

// --- Длительные работы ---
export 'src/async/async_operation.dart';
export 'src/async/operation_request.dart';
export 'src/async/operation_status.dart';
export 'src/async/progress_report.dart';
export 'src/async/transfer_progress.dart';

// --- Вид списка ---
export 'src/panel/column_spec.dart';
export 'src/panel/entry_condition.dart';
export 'src/panel/file_icon_rule.dart';
export 'src/panel/sort_spec.dart';

// --- Настройки ---
export 'src/serialization.dart';
export 'src/settings/app_settings.dart';
export 'src/settings/module_settings.dart';
export 'src/settings/window_geometry.dart';

// --- Модули ---
export 'src/module/fc_module.dart';

// --- Система ---
//
// Службы, которые **зовёт** одна сторона, а **исполняет** другая: секреты
// спрашивает источник, а показывает окно интерфейс; открыть файл системой
// просит команда, а запускает ядро. Интерфейс у таких служб общий, а кто по
// какую сторону — решает сборка.
export 'src/os/credentials.dart';
export 'src/os/elevation.dart';
export 'src/os/pty_session.dart';
export 'src/os/system_opener.dart';

// --- Форматирование и утилиты ---
export 'src/format/date_format.dart';
export 'src/format/duration_format.dart';
export 'src/format/size_format.dart';
export 'src/util/file_mask.dart';
export 'src/util/file_name.dart';
export 'src/util/natural_compare.dart';
export 'src/util/throttle.dart';
