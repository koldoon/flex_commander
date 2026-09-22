import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Служба оформления — подставная: настоящая живёт в приложении, а накладке
/// нужен только контракт.
class _Themes extends ChangeNotifier implements ThemeService {
  _Themes(List<FcThemeSpec> themes) : _themes = [...themes], _currentId = themes.first.id;

  final List<FcThemeSpec> _themes;
  String _currentId;

  int notifications = 0;

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
    notifications++;
    notifyListeners();
  }

  @override
  void use(String id) {
    _currentId = id;
    notifications++;
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

const _light = FcThemeSpec(
  id: 'light',
  title: 'Light',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

void main() {
  late _Themes themes;
  late ThemeOverrides overrides;
  late ThemeOverlay overlay;
  var saves = 0;

  setUp(() {
    themes = _Themes([_default, _light]);
    overrides = ThemeOverrides();
    saves = 0;
    overlay = ThemeOverlay(themes: themes, overrides: overrides, save: () => saves++)..start();
  });

  tearDown(() => overlay.stop());

  test('правка перекрашивает приложение и запоминается', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

    expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    // Прочее осталось темы: накладка — своё там, где задано.
    expect(themes.current.colors.windowBackground, const DefaultColors().windowBackground);
    expect(overrides.baseThemeId, 'default');
    expect(saves, 1);
  });

  test('своё уведомление не ловится: первая правка не уходит в круг', () {
    // Подстановка будит тот же слушатель, на котором висит редактор. Признак
    // «это наша накладка» и есть всё, что отделяет правку от вечного цикла.
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

    expect(themes.notifications, 1);
  });

  test('вторая правка кладётся на тему, а не на первую правку', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    overlay.setMetric('rowHeight', 26);

    // База помнится до первой подстановки: иначе накладки складывались бы
    // стопкой, и «Reset» одной роли возвращал бы предыдущую правку.
    expect(themes.current.metrics.rowHeight, 26);
    expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    expect(overlay.pristine.metrics.rowHeight, const DefaultMetrics().rowHeight);
  });

  test('возврат роли возвращает умолчание темы, а не прошлую правку', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    overlay.setColor('cursorBackground', const Color(0xFFDE1D2E));
    overlay.setColor('cursorBackground', null);

    expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);
  });

  test('пустая накладка прослойкой не остаётся', () {
    overlay.setMetric('rowHeight', 26);
    final count = overlay.resetAll();

    expect(count, 1);
    expect(identical(themes.current, _default), isTrue, reason: 'в службу вернулась сама тема');
  });

  test('накладка сделана для своей темы: на чужой не применяется', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

    themes.use('light');
    expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);

    // Вернулись — легла снова.
    themes.use('default');
    expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
  });

  test('правка на другой теме начинает накладку заново', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    themes.use('light');
    overlay.setMetric('rowHeight', 26);

    expect(overrides.baseThemeId, 'light');
    expect(overrides.colors, isEmpty, reason: 'цвета, подобранные к одной теме, другой не годятся');
    expect(themes.current.metrics.rowHeight, 26);

    // Прежней теме вернулся её собственный вид: иначе она до перезапуска
    // показывала бы правки, которых в настройках уже нет.
    themes.use('default');
    expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);
    expect(themes.current.metrics.rowHeight, const DefaultMetrics().rowHeight);
  });

  test('тему перевыложил её модуль — накладка ложится на свежую базу', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

    // Модуль темы объявил себя заново — с другим фоном окна.
    themes.register(
      const FcThemeSpec(
        id: 'default',
        title: 'Default',
        colors: _OtherColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      ),
    );

    expect(themes.current.colors.windowBackground, const Color(0xFF101010));
    expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF), reason: 'правка цела');
  });

  test('прочитанная из настроек накладка применяется при запуске', () {
    final stored =
        ThemeOverrides()..fromMap({
          'baseThemeId': 'default',
          'colors': {'cursorBackground': '#FF2D6CDF', 'такой роли нет': 'не цвет'},
          'metrics': {'rowHeight': 26},
          'fonts': {
            'fixed': 'JetBrains Mono',
            'fixedFallback': ['Menlo'],
          },
        });
    final fresh = _Themes([_default, _light]);
    ThemeOverlay(themes: fresh, overrides: stored, save: () {}).start();

    expect(fresh.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    expect(fresh.current.metrics.rowHeight, 26);
    expect(fresh.current.fonts.fixed, 'JetBrains Mono');
    expect(fresh.current.fonts.fixedFallback, ['Menlo']);
    // Испорченное — мимо, а не падение разбора (сквозное правило 5).
    expect(stored.colors.keys, ['cursorBackground']);
  });

  test('накладка записывается строками и читается обратно', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    overlay.setMetric('rowHeight', 26);
    overlay.setFixedFont('JetBrains Mono');

    final written = <String, dynamic>{};
    overrides.toMap(written);
    expect(written['colors'], {'cursorBackground': '#FF2D6CDF'});
    expect(written['metrics'], {'rowHeight': 26.0});
    expect(written['fonts'], {'fixed': 'JetBrains Mono'});

    final read = ThemeOverrides()..fromMap(written);
    expect(read.colors['cursorBackground'], const Color(0xFF2D6CDF));
    expect(read.metrics['rowHeight'], 26.0);
    expect(read.fixedFont, 'JetBrains Mono');
  });
}

/// Тема, объявленная заново: важен только изменившийся фон окна.
class _OtherColors extends DefaultColors {
  const _OtherColors();

  @override
  Color get windowBackground => const Color(0xFF101010);
}
