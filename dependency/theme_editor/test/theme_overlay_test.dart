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
  void forget(String id) {
    _themes.removeWhere((theme) => theme.id == id);
    if (!_themes.any((theme) => theme.id == _currentId)) {
      _currentId = _themes.first.id;
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
    expect(overrides.find('default')?.colors, {'cursorBackground': const Color(0xFF2D6CDF)});
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

  test('у каждой темы правки свои', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    themes.use('light');
    overlay.setMetric('rowHeight', 26);

    // Цвета, подобранные к одной теме, другой не годятся: правки не переезжают.
    expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);
    expect(themes.current.metrics.rowHeight, 26);

    themes.use('default');
    expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
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
          'themes': [
            {
              'id': 'default',
              'base': 'default',
              'colors': {'cursorBackground': '#FF2D6CDF', 'такой роли нет': 'не цвет'},
              'metrics': {'rowHeight': 26},
              'fonts': {
                'fixed': 'JetBrains Mono',
                'fixedFallback': ['Menlo'],
              },
            },
            // Запись без имени темы — не запись вовсе: применять её не к чему.
            {'base': 'default'},
          ],
        });
    final fresh = _Themes([_default, _light]);
    ThemeOverlay(themes: fresh, overrides: stored, save: () {}).start();

    expect(fresh.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    expect(fresh.current.metrics.rowHeight, 26);
    expect(fresh.current.fonts.fixed, 'JetBrains Mono');
    expect(fresh.current.fonts.fixedFallback, ['Menlo']);
    // Испорченное — мимо, а не падение разбора (сквозное правило 5).
    expect(stored.themes, hasLength(1));
    expect(stored.themes.single.colors.keys, ['cursorBackground']);
  });

  group('своя тема', () {
    test('складывается из того, что на экране, и становится выбранной', () {
      overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

      final id = overlay.create('My dark');

      expect(id, 'my-dark', reason: 'имя по названию: его видно в файле настроек');
      expect(themes.current.id, 'my-dark');
      expect(themes.current.title, 'My dark');
      // Копией нынешних правок, а не пустой: «New» нажимают, доведя оформление
      // до нужного.
      expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
      // И встроенная осталась при своём.
      themes.use('default');
      expect(themes.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    });

    test('правится отдельно от той, с которой списана', () {
      overlay.create('My dark');
      overlay.setColor('cursorBackground', const Color(0xFFDE1D2E));

      expect(themes.current.colors.cursorBackground, const Color(0xFFDE1D2E));
      themes.use('default');
      expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);
    });

    test('«Reset all» возвращает её к базе, но не убирает из списка', () {
      overlay.create('My dark');
      overlay.setColor('cursorBackground', const Color(0xFFDE1D2E));

      expect(overlay.resetAll(), 1);
      expect(themes.current.id, 'my-dark', reason: 'тема без правок — это всё ещё тема');
      expect(themes.current.colors.cursorBackground, const DefaultColors().cursorBackground);
    });

    test('имена не сталкиваются', () {
      overlay.create('My dark');
      themes.use('default');

      expect(overlay.create('My dark'), 'my-dark-2');
    });

    test('убирается вместе с правками, и выбор переходит её базе', () {
      final id = overlay.create('My dark');

      expect(overlay.remove(id), isTrue);
      expect(themes.available.map((theme) => theme.id), isNot(contains('my-dark')));
      expect(themes.current.id, 'default');
      expect(overrides.find('my-dark'), isNull);
    });

    test('встроенную убрать нельзя: её объявил модуль', () {
      overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

      expect(overlay.remove('default'), isFalse);
      expect(themes.available.map((theme) => theme.id), contains('default'));
    });

    test('переживает перезапуск вместе с правками', () {
      overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
      overlay.create('My dark');

      final written = <String, dynamic>{};
      overrides.toMap(written);

      final fresh = _Themes([_default, _light]);
      ThemeOverlay(themes: fresh, overrides: ThemeOverrides()..fromMap(written), save: () {}).start();

      expect(fresh.available.map((theme) => theme.id), contains('my-dark'));
      fresh.use('my-dark');
      expect(fresh.current.title, 'My dark');
      expect(fresh.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    });
  });

  test('накладка записывается строками и читается обратно', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    overlay.setMetric('rowHeight', 26);
    overlay.setFixedFont('JetBrains Mono');

    final written = <String, dynamic>{};
    overrides.toMap(written);
    final stored = (written['themes'] as List).single as Map<String, dynamic>;
    expect(stored['id'], 'default');
    expect(stored['colors'], {'cursorBackground': '#FF2D6CDF'});
    expect(stored['metrics'], {'rowHeight': 26.0});
    expect(stored['fonts'], {'fixed': 'JetBrains Mono'});

    final read = (ThemeOverrides()..fromMap(written)).themes.single;
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
