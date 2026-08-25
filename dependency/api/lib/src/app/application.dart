import 'package:flutter/foundation.dart';

import '../background/operations.dart';
import '../commands/command_service.dart';
import 'errors.dart';
import 'panel_viewport.dart';
import 'viewport.dart';
import 'views.dart';
import '../theme/theme_service.dart';
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

  /// Заведённые работы: их показывают статусные области.
  Operations get operations;

  /// Ошибки, которые никто не поймал: показать человеку, а не только записать
  /// в журнал.
  Errors get errors;

  /// Всплывающие сообщения: сказать о том, что случилось и уже закончилось.
  Toasts get toasts;

  /// Пароли и прочие секреты: спросить у пользователя то, без чего дальше
  /// нельзя. Модули получают ту же службу через `services.resolve<Credentials>()`.
  Credentials get credentials;

  /// Чем рисуется содержимое панелей.
  PanelViewports get viewports;

  /// Чем рисуются состояния: панель, просмотрщик, заявка от работы.
  ///
  /// Вид ищется по самому состоянию, а не по имени вида: связь между ними
  /// проверяет компилятор, и модуль, объявивший состояние, объявляет и вид.
  Views get views;

  /// Рабочая область: что где стоит и кому принадлежит ввод.
  ///
  /// Сами файловые панели — такое же содержимое области, как просмотрщик или
  /// результаты поиска: ядро не решает, чем показывать файлы.
  ApplicationView get view;

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
