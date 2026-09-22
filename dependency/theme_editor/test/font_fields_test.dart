import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Служба оформления — подставная, как и в соседнем тесте: накладке нужен
/// только контракт.
class _Themes extends ChangeNotifier implements ThemeService {
  _Themes(this._themes) : _currentId = _themes.first.id;

  final List<FcThemeSpec> _themes;
  String _currentId;

  @override
  List<FcThemeSpec> get available => List.unmodifiable(_themes);

  @override
  FcThemeSpec get current => _themes.firstWhere((theme) => theme.id == _currentId);

  @override
  void register(FcThemeSpec spec) {
    final at = _themes.indexWhere((theme) => theme.id == spec.id);
    if (at >= 0) {
      _themes[at] = spec;
    } else {
      _themes.add(spec);
    }
    notifyListeners();
  }

  @override
  void forget(String id) {
    _themes.removeWhere((theme) => theme.id == id);
    notifyListeners();
  }

  @override
  void use(String id) {
    _currentId = id;
    notifyListeners();
  }
}

const _default = FcThemeSpec(
  id: 'default',
  title: 'Default',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

/// Поля шрифтов в окне редактора (`docs/spec/theme-editor.md`, §12).
void main() {
  late ThemeOverlay overlay;
  late _Themes themes;

  setUp(() {
    themes = _Themes([_default]);
    overlay = ThemeOverlay(themes: themes, overrides: ThemeOverrides(), save: () {})..start();
  });

  tearDown(() => overlay.stop());

  SettingsField fieldOf(String id, {List<SystemFont> fonts = const []}) => themeEditorPages(
    themes,
    overlay,
    save: () {},
    fonts: fonts,
  ).expand((page) => page.build().fields).firstWhere((field) => field.id == id);

  test('перечня нет — шрифт набирают руками', () {
    // Служба платформенная, и её может не быть: другая система, тест,
    // выключенный модуль. Поле остаётся строкой, и это работает.
    expect(fieldOf('ui'), isA<SettingsText>());
    expect(fieldOf('fixed'), isA<SettingsText>());
  });

  test('перечень есть — шрифт выбирают списком', () {
    const installed = [
      SystemFont(family: 'Ubuntu', fixedPitch: false),
      SystemFont(family: 'Menlo', fixedPitch: true),
      SystemFont(family: 'Monotype Corsiva', fixedPitch: false),
    ];

    final ui = fieldOf('ui', fonts: installed) as SettingsChoice;
    expect(ui.options.keys, contains('Ubuntu'));
    expect(ui.options.keys, contains('Monotype Corsiva'));

    // Списку файлов — только моноширинные: пропорциональным шрифтом столбцы
    // размеров и дат перестают стоять столбцами.
    final fixed = fieldOf('fixed', fonts: installed) as SettingsChoice;
    expect(fixed.options.keys, contains('Menlo'));
    expect(fixed.options.keys, isNot(contains('Monotype Corsiva')));
  });

  test('неустановленный шрифт темы всё равно в списке', () {
    // У темы по умолчанию это Consolas: на macOS его обычно нет, а выбранным в
    // списке он обязан показаться — иначе поле врёт про то, что стоит.
    const installed = [SystemFont(family: 'Menlo', fixedPitch: true)];
    final fixed = fieldOf('fixed', fonts: installed) as SettingsChoice;

    expect(fixed.options.keys, contains(const DefaultFonts().fixed));
    expect(fixed.read(), const DefaultFonts().fixed);
  });

  test('выбранный список едет в накладку, а темин — снимает правку', () {
    const installed = [SystemFont(family: 'Menlo', fixedPitch: true)];

    (fieldOf('fixed', fonts: installed) as SettingsChoice).write('Menlo');
    expect(themes.current.fonts.fixed, 'Menlo');

    (fieldOf('fixed', fonts: installed) as SettingsChoice).write(const DefaultFonts().fixed);
    expect(overlay.currentEdit.fixedFont, isNull, reason: 'запись, повторяющая тему, правкой не считается');
  });
}
