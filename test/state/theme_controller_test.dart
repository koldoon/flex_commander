import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Светлая палитра «на пробу»: важно не то, какие в ней цвета, а то, что она
/// подменяется целиком и без правки виджетов.
class _LightColors extends FcColors {
  const _LightColors();

  @override
  Color get windowBackground => const Color(0xFFF5F5F5);
}

const _light = FcThemeSpec(id: 'light', title: 'Light', brightness: Brightness.light, colors: _LightColors());

void main() {
  test('без единой темы работают умолчания API', () {
    final themes = ThemeController();

    expect(themes.available, isEmpty);
    expect(themes.current.id, FcThemeSpec.fallback.id);
    expect(themes.current.colors.windowBackground, const FcColors().windowBackground);
  });

  test('установленная тема становится текущей', () {
    final themes = ThemeController([_light]);

    expect(themes.available.map((theme) => theme.id), ['light']);
    expect(themes.current.id, 'light');
  });

  test('переключение меняет оформление и уведомляет', () {
    final themes = ThemeController([FcThemeSpec.fallback, _light]);
    var notifications = 0;
    themes.addListener(() => notifications++);

    themes.use('light');

    expect(themes.current.colors.windowBackground, const _LightColors().windowBackground);
    expect(notifications, 1);
  });

  test('незнакомое имя игнорируется', () {
    final themes = ThemeController([FcThemeSpec.fallback]);
    var notifications = 0;
    themes.addListener(() => notifications++);

    // В настройках могло остаться имя от модуля, который сейчас отключён:
    // запуск из-за этого падать не должен.
    themes.use('solarized');

    expect(themes.current.id, FcThemeSpec.fallback.id);
    expect(notifications, isZero);
  });

  test('повторная установка заменяет тему, а не заводит вторую', () {
    final themes = ThemeController([_light]);

    themes.register(const FcThemeSpec(id: 'light', title: 'Light (updated)'));

    expect(themes.available, hasLength(1));
    expect(themes.available.single.title, 'Light (updated)');
  });

  test('тема несёт иконки и шрифты, а не только цвета', () {
    const spec = FcThemeSpec(
      id: 'big',
      title: 'Big',
      metrics: FcMetrics(scale: 0.8, fontScale: 0.7),
      icons: FcIcons(fontFamily: 'OtherIcons'),
      fonts: FcFonts(ui: 'Inter', fixed: 'Menlo'),
    );

    // Масштаб — одно число на весь интерфейс: это и есть «крупная» тема.
    expect(spec.metrics.rowHeight, 50 * 0.8);
    expect(spec.theme.uiStyle.fontFamily, 'Inter');
    expect(spec.theme.rowStyle.fontFamily, 'Menlo');
    expect(spec.icons.folder.fontFamily, 'OtherIcons');
  });
}
