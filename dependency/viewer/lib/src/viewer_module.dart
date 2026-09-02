import 'package:fc_ui_api/fc_ui_api.dart';

import 'quick_view_screen.dart';
import 'quick_view_view.dart';
import 'view_commands.dart';

/// Оболочка просмотра: `F3`, `Shift-F3` и выбор того, чем показывать.
///
/// Сама она не показывает ничего. Показывают просмотрщики — они объявляют себя
/// в общий реестр (`registry.viewer`), а эта оболочка спрашивает, кто возьмётся
/// за файл, и ставит выбранное в область: во весь экран или наложением на
/// соседнюю панель.
///
/// Выключите её — просмотра не будет вовсе, кто бы что ни объявил. Выключите
/// отдельный просмотрщик — пропадёт только он: `F3` останется и ответит
/// отказом там, где взяться теперь некому.
class Viewer implements FcFrontendModule {
  const Viewer();

  @override
  String get id => 'fc.viewer';

  @override
  String get title => 'Viewer';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<QuickViewHost>((context, state) => QuickViewView(host: state));

    registry.command((context) => ViewFileCommand());
    registry.command((context) => QuickViewCommand());
    registry.command((context) => CloseViewerCommand());

    // Быстрый просмотр — в слое `Shift` рядом с `F3`: то же действие, только
    // рядом, а не во весь экран.
    registry.binding(KeyBinding('Shift-F3', QuickViewCommand.commandId));

    // Закрытие — одно на все просмотрщики: `inState<ViewerContent>` подходит
    // любому показу, чем бы он ни был, и объявлено это здесь один раз.
    registry.binding(KeyBinding.inState<ViewerContent>('Esc', CloseViewerCommand.commandId));
    registry.binding(KeyBinding.inState<ViewerContent>('F10', CloseViewerCommand.commandId));

    // И для хозяина отдельно: показывать ему бывает нечего — под курсором
    // каталог, — а уйти из него всё равно нужно.
    registry.binding(KeyBinding.inState<QuickViewHost>('Esc', CloseViewerCommand.commandId));
    registry.binding(KeyBinding.inState<QuickViewHost>('F10', CloseViewerCommand.commandId));

    // `Tab` из быстрого просмотра — обратно к файлам. Клавиша панелей сюда не
    // достаёт: содержимое активной области больше не панель. Команда общая, по
    // идентификатору: модуля навигации может не быть, и тогда клавиша молчит.
    registry.binding(KeyBinding.inState<QuickViewHost>('Tab', 'app.togglePanel'));
  }
}
