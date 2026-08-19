import 'package:flutter/foundation.dart';

import '../background/task_status.dart';
import '../commands/command_service.dart';
import '../ui/panel_viewport.dart';
import '../ui/theme/theme_service.dart';
import '../settings/app_settings.dart';
import '../settings/module_settings.dart';
import '../settings/window_geometry.dart';
import '../os/credentials.dart';
import 'panel.dart';
import 'toasts.dart';

/// Приложение целиком — то, чем оперируют команды.
///
/// Аналог `IApplication` референса. Вместе с [Panel] и [PanelSelection] это и
/// есть API для написания команд: всё, что команде нужно знать о приложении,
/// описано здесь, а как это устроено внутри — её не касается.
///
/// [Listenable] — часть контракта, а не подробность реализации: тот, кто рисует
/// приложение или следит за ним из модуля, подписывается на интерфейс и не
/// обязан знать про `AppController`.
abstract interface class Application implements Listenable {
  Panel get left;

  Panel get right;

  /// Активная панель — источник операции.
  Panel get activePanel;

  /// Пассивная панель — приёмник операции.
  Panel get passivePanel;

  /// Действия приложения и клавиши за ними.
  ///
  /// Через него модуль ставит свои команды, а нижняя панель узнаёт, что висит
  /// на `F5` прямо сейчас.
  CommandService get commands;

  /// Оформление приложения: какое есть и какое выбрано.
  ThemeService get theme;

  /// Работы, ушедшие в фон.
  BackgroundTasks get background;

  /// Всплывающие сообщения: сказать о том, что случилось и уже закончилось.
  Toasts get toasts;

  /// Пароли и прочие секреты: спросить у пользователя то, без чего дальше
  /// нельзя. Модули получают ту же службу через `services.resolve<Credentials>()`.
  Credentials get credentials;

  /// Чем рисуется содержимое панелей.
  PanelViewports get viewports;

  /// Закрывает окно запущенной команды.
  ///
  /// Команда получает идентификатор запуска при создании и просит закрыть
  /// именно своё окно: одновременно могут работать несколько команд.
  void closeDialog(String runId);

  void activate(Panel panel);

  /// Переключить активную панель.
  void toggleActivePanel();

  /// Доля ширины окна под левой панелью.
  double get splitRatio;

  void setSplitRatio(double value);

  /// Последняя известная геометрия окна.
  WindowGeometry? get windowGeometry;

  /// Текущее состояние приложения в виде сохраняемых настроек.
  AppSettings get settings;

  /// Раздел настроек модуля. Имя — идентификатор модуля.
  SettingsScope moduleSettings(String namespace);

  /// Запуск: восстановление окна и каталогов.
  Future<void> start();

  /// Завершение: сохранение настроек и остановка операций.
  Future<void> shutdown();
}
