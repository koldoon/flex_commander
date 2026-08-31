import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Настройки: всё, что человек выбирает, в одном окне.
///
/// Окно, а не экран: полей немного, они умещаются с прокруткой, а окно уже
/// умеет ровно то, что нужно, — `Tab` по полям, `Esc`, возврат фокуса туда,
/// откуда пришли (`spec/dialog-focus.md`). Экран пришлось бы учить этому
/// заново ради места, которое пока некуда девать.
class SettingsCommand extends AppCommand {
  SettingsCommand({required SettingsCatalog Function() catalog}) : _catalog = catalog;

  /// Разделы — способом их спросить: во время создания команды служб ещё нет.
  final SettingsCatalog Function() _catalog;

  static const String commandId = 'app.settings';

  @override
  String get id => commandId;

  @override
  String get label => 'Settings';

  @override
  String get description => 'Everything the application remembers by your choice';

  /// `Preferences` — то же самое словом другой школы; `config` — привычка из
  /// терминала.
  @override
  Set<String> get keywords => const {'preferences', 'options', 'config', 'setup'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        title: 'Settings',
        takesFocus: true,
        // Ширину окно задаёт само — долей экрана, а не точками: с общим
        // верхним пределом на широком экране оно обрезалось бы тем сильнее,
        // чем экран шире.
        ownWidth: true,
        content: FcSettingsForm(pages: _catalog().pages, onClose: close),
        // Подтверждать нечего: изменение уже применилось, `Enter` просто
        // закрывает.
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }
}
