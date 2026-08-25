import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'state/app_controller.dart';
import 'view/app_shell.dart';
import 'view/theme/app_theme.dart';

class FlexCommanderApp extends StatefulWidget {
  const FlexCommanderApp({super.key, required this.controller});

  final AppController controller;

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
        // Оформление меняется отдельно от остального состояния: тему
        // выбирает команда, а не панель, — поэтому подписки две.
        listenable: Listenable.merge([widget.controller, widget.controller.theme]),
        builder:
            (context, child) => MaterialApp(
              title: 'Flex Commander',
              debugShowCheckedModeBanner: false,
              theme: buildThemeData(widget.controller.theme.current),
              home: const AppShell(),
            ),
      ),
    );
  }
}
