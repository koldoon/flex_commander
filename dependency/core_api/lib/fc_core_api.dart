/// API ядра Flex Commander: то, против чего пишется серверная часть модуля.
///
/// Дерево узлов и источники, монтирование и аренда, движок переноса, службы
/// системы. Экрана у этой стороны нет: ни окна, ни команды, ни виджета здесь
/// не встретится, а `fc_ui_api` эта сторона не видит вовсе
/// (`spec/client-server.md`, §3).
///
/// `dart:io` в пакете нет: платформа живёт в модулях, а не в API.
library;

// --- Дерево и источники ---
export 'src/tree/fs_node.dart';
export 'src/tree/node_path.dart';
export 'src/tree/node_sorting.dart';
export 'src/tree/operation_params.dart';
export 'src/tree/provider_lease.dart';
export 'src/tree/provider_registry.dart';
export 'src/tree/staging.dart';
export 'src/tree/tree_provider.dart';

// --- Перенос ---
export 'src/tree/transfer/local_copy_session.dart';
export 'src/tree/transfer/transfer_answers.dart';
export 'src/tree/transfer/transfer_engine.dart';
export 'src/tree/transfer/write_back.dart';

// --- Система ---
export 'src/os/elevated_sink.dart';
export 'src/os/elevation.dart';
export 'src/os/process_runner.dart';
export 'src/os/pty.dart';
