import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'view/application_view.dart';
import 'view/theme/app_theme.dart';

class FlexCommanderApp extends StatelessWidget {
  const FlexCommanderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder:
            (context, child) => MaterialApp(
              title: 'Flex Commander',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: AppTheme.themeModeOf(controller.themeMode),
              home: const ApplicationView(),
            ),
      ),
    );
  }
}
