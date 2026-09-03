import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/panel_mirror.dart';

/// Панель для проверок — обе её половины разом.
///
/// Экран видит зеркало, ядро держит сеанс, между ними петля. Проверка обычно
/// говорит с [PanelMirror] — это и есть панель, какой её видят команды, — но
/// иногда ей нужна и та сторона: узлы, провайдер, монтирование. Тогда она
/// спрашивает [session], и в коде видно, что вопрос был про ядро.
class TestPanel extends PanelMirror {
  TestPanel._({
    required super.id,
    required super.link,
    required super.state,
    required super.listing,
    required this.session,
    required this.core,
  });

  /// Панель со стороны ядра: узлы, провайдер, аренда.
  final PanelSession session;

  /// Ядро, поднятое ради этой панели: работы, содержимое, оболочки.
  final CoreServer core;

  /// Закрывает обе половины.
  ///
  /// В приложении сеансы закрывает ядро, а зеркало — только себя; здесь ядро
  /// заведено ради этой панели, и уходят они вместе.
  @override
  void dispose() {
    unawaited(core.dispose());
    super.dispose();
  }
}

/// Панель на подставном провайдере — вместе с ядром, которое её держит.
///
/// Реестр провайдеров и движок файловых операций панель себе не подставляет:
/// чем открываются вложенные источники и каким движком выполняются операции —
/// решение сборки приложения, а не панели. Тесту это решение обычно
/// безразлично, поэтому умолчания живут здесь: один источник и обычный движок.
TestPanel testPanel({
  required TreeProvider provider,
  required PanelSettings settings,
  ProviderRegistry? registry,
  TreeEditor editor = const TreeTransferEngine(),
  int sizeScanConcurrency = AppSettings.defaultSizeScanConcurrency,
  PanelId id = PanelId.left,
}) {
  final providers = registry ?? ProviderRegistry(root: provider);
  final session = PanelSession(
    settings: settings,
    registry: providers,
    editor: editor,
    sizeScanConcurrency: () => sizeScanConcurrency,
  );
  // Вторая панель ядру нужна всегда — оно про две, — но проверке она не мешает:
  // стоит на том же источнике и никем не трогается.
  final other = PanelSession(settings: PanelSettings(), registry: providers, editor: editor);
  final core = CoreServer(
    left: id == PanelId.left ? session : other,
    right: id == PanelId.left ? other : session,
    registry: providers,
    editor: editor,
  );
  final Link link = LoopbackLink(core);

  return TestPanel._(
    id: id,
    link: link,
    state: session.state,
    listing: PanelListing(generation: session.generation, entries: session.entries),
    session: session,
    core: core,
  );
}
