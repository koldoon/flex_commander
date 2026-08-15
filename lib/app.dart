import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'view/application_view.dart';
import 'view/theme/app_theme.dart';

class FlexCommanderApp extends StatefulWidget {
  const FlexCommanderApp({super.key, required this.controller, this.navigatorKey});

  final AppController controller;

  /// Ключ навигатора, через который команды показывают диалоги: они выполняются
  /// вне дерева виджетов, и другого доступа к нему у них нет.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<FlexCommanderApp> createState() => _FlexCommanderAppState();
}

class _FlexCommanderAppState extends State<FlexCommanderApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Система спрашивает разрешение на выход: это единственный момент, когда
    // можно дописать настройки до того, как процесс завершится.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.shutdown();
        return AppExitResponse.exit;
      },
      // Уход на второй план — удобный момент забрать геометрию окна:
      // в обработчике завершения это делать уже поздно.
      onInactive: widget.controller.captureWindowGeometry,
      onHide: widget.controller.captureWindowGeometry,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder:
            (context, child) => MaterialApp(
              title: 'Flex Commander',
              navigatorKey: widget.navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: AppTheme.themeModeOf(widget.controller.themeMode),
              home: const ApplicationView(),
            ),
      ),
    );
  }
}
