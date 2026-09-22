import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

import 'overlay_colors.dart';
import 'overlay_fonts.dart';
import 'overlay_metrics.dart';
import 'theme_overrides.dart';

/// Накладка поверх темы: правки живут здесь, а приложение перекрашивается
/// обычной подменой темы (`docs/spec/theme-editor.md`, §5).
///
/// Своего пути до экрана у редактора нет: `ThemeService.register` с тем же
/// `id` заменяет прежнюю тему — это в контракте с самого начала. Своя тема
/// человека объявляется тем же способом, только под своим именем.
class ThemeOverlay {
  ThemeOverlay({required this.themes, required this.overrides, required this.save});

  final ThemeService themes;
  final ThemeOverrides overrides;

  /// Как попросить сохранить раздел настроек.
  final void Function() save;

  /// Темы без правок — те, на которые всё кладётся.
  ///
  /// **Помнятся до первой подстановки.** Зарегистрировав накладку под именем
  /// темы, редактор вытесняет её саму из списка службы — и вторую правку класть
  /// было бы не на что. Иначе накладки складывались бы стопкой, а «Reset» одной
  /// роли возвращал бы не умолчание, а предыдущую правку.
  final Map<String, FcThemeSpec> _pristine = {};

  /// Что мы сами положили в службу — по нему своё уведомление отличается от
  /// чужого.
  final Map<String, FcThemeSpec> _applied = {};

  bool _applying = false;

  /// Начать следить за оформлением и положить накладки.
  void start() {
    themes.addListener(_themeChanged);
    applyAll();
  }

  void stop() => themes.removeListener(_themeChanged);

  /// Правки темы, что на экране; заводит их, если правок ещё не было.
  ///
  /// Правят **ту тему, что на экране** — свою или встроенную, всё равно: у
  /// каждой свои правки, и смешивать их нельзя. Цвета, подобранные к тёмной,
  /// светлую испортят.
  ThemeEdit get currentEdit {
    final current = themes.current;
    final known = overrides.find(current.id);
    if (known != null) {
      return known;
    }
    // Правок ещё нет: значит, это встроенная тема, и накладка ляжет на неё.
    _pristine.putIfAbsent(current.id, () => current);
    return overrides.edit(current.id, base: current.id);
  }

  /// Тема без правок — та, поверх которой лежит нынешняя.
  ///
  /// С ней форма сравнивает значения ролей, решая, тронута ли настройка. У
  /// своей темы это её база, а не она сама: «Reset» роли возвращает то, с чего
  /// тема начиналась.
  FcThemeSpec get pristine => baseOf(currentEdit);

  FcThemeSpec baseOf(ThemeEdit edit) =>
      _pristine[edit.base] ?? themes.available.where((theme) => theme.id == edit.base).firstOrNull ?? themes.current;

  /// Поправить цвет; null — забыть правку этой роли.
  void setColor(String role, Color? value) => _edit((edit) => _put(edit.colors, role, value));

  /// Поправить размер; null — забыть правку.
  void setMetric(String role, double? value) => _edit((edit) => _put(edit.metrics, role, value));

  void setUiFont(String? value) => _edit((edit) => edit.uiFont = value);

  void setFixedFont(String? value) => _edit((edit) => edit.fixedFont = value);

  void setFallback(List<String>? value) => _edit((edit) => edit.fallback = value);

  /// Забыть правки темы, что на экране; возвращает, сколько их было.
  int resetAll() {
    final edit = currentEdit;
    final count = edit.length;
    if (count == 0) {
      return 0;
    }
    edit.clear();
    save();
    apply(edit);
    return count;
  }

  /// Сложить свою тему из того, что на экране, и перейти на неё.
  ///
  /// Копией нынешних правок, а не пустой: человек нажал «New», доведя
  /// оформление до нужного, — потерять эту работу было бы хуже всего. Тем же
  /// устроен «New» у наборов выбора (`docs/spec/settings-presets.md`, §6).
  ///
  /// Возвращает имя новой темы.
  String create(String title) {
    final edit = currentEdit.copyAs(id: _freeId(title), title: title);
    // Своя тема кладётся на **ту же базу**, что и нынешняя: тема поверх темы
    // означала бы стопку накладок, у которой не видно дна.
    overrides.add(edit);
    save();
    apply(edit);
    themes.use(edit.id);
    return edit.id;
  }

  /// Убрать свою тему; встроенную убрать нельзя — её объявил модуль.
  ///
  /// Возвращает, убрали ли: нечего убирать — значит и говорить не о чем.
  bool remove(String id) {
    final edit = overrides.find(id);
    if (edit == null || !edit.isOwn) {
      return false;
    }
    final base = edit.base;
    overrides.remove(id);
    _applied.remove(id);
    save();
    _applying = true;
    themes.forget(id);
    _applying = false;
    // На базу, а не на первую попавшуюся: человек правил её копию, и вернуться
    // ему естественнее туда, откуда он начал.
    themes.use(base);
    return true;
  }

  /// Положить все накладки: правки встроенных тем и свои темы человека.
  void applyAll() {
    // Встроенные запоминаются **до** первой подстановки: иначе своя тема легла
    // бы на уже поправленную.
    for (final theme in themes.available) {
      _pristine.putIfAbsent(theme.id, () => theme);
    }
    for (final edit in overrides.themes) {
      apply(edit);
    }
  }

  /// Собрать накладку и объявить её под именем её темы.
  ///
  /// Пусто — в службу возвращается сама тема: накладка, из которой убрали всё,
  /// не должна оставаться прослойкой. Со своей темой не так: без правок она всё
  /// равно стоит в списке — это тема, а не правка.
  void apply(ThemeEdit edit) {
    final base = _pristine[edit.base] ?? themes.available.where((theme) => theme.id == edit.base).firstOrNull;
    if (base == null) {
      // Темы с таким именем нет: её модуль могли отключить между запусками.
      // Правки при этом целы и ждут (§6).
      return;
    }

    final spec =
        edit.isEmpty && !edit.isOwn
            ? base
            : FcThemeSpec(
              id: edit.id,
              title: edit.isOwn ? edit.title : base.title,
              brightness: base.brightness,
              colors: OverlayColors(base.colors, edit.colors),
              metrics: OverlayMetrics(base.metrics, edit.metrics),
              // Глифы иконок не правятся: это кодовые точки шрифта, и
              // перебирать их вслепую человеку не по чему (§12).
              icons: base.icons,
              fonts: OverlayFonts(base.fonts, uiFont: edit.uiFont, fixedFont: edit.fixedFont, fallback: edit.fallback),
            );

    _applied[edit.id] = spec;
    _applying = true;
    themes.register(spec);
    _applying = false;
  }

  /// Правка темы, что на экране.
  void _edit(void Function(ThemeEdit edit) change) {
    final edit = currentEdit;
    change(edit);
    save();
    apply(edit);
  }

  void _put<T>(Map<String, T> where, String role, T? value) {
    if (value == null) {
      where.remove(role);
    } else {
      where[role] = value;
    }
  }

  /// Свободное имя для своей темы: по названию, а не по счётчику — его видно в
  /// файле настроек, и «My dark» там понятнее, чем «theme3».
  String _freeId(String title) {
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final stem = slug.isEmpty ? 'theme' : slug;
    if (_free(stem)) {
      return stem;
    }
    for (var at = 2; ; at++) {
      if (_free('$stem-$at')) {
        return '$stem-$at';
      }
    }
  }

  bool _free(String id) => overrides.find(id) == null && !themes.available.any((theme) => theme.id == id);

  /// Тему сменили или перевыложили — и это могло быть не нами.
  ///
  /// Признак «это наша накладка» обязан быть: подстановка сама будит этот же
  /// слушатель, и без него первая же правка ушла бы в вечный круг (§5).
  void _themeChanged() {
    if (_applying) {
      return;
    }
    for (final edit in overrides.themes) {
      final spec = themes.available.where((theme) => theme.id == edit.base).firstOrNull;
      if (spec == null || identical(spec, _applied[edit.base]) || identical(spec, _pristine[edit.base])) {
        continue;
      }
      // Тему перевыложил её модуль: класть накладку надо на свежую базу, а не
      // на ту, что запомнили в прошлый раз.
      _pristine[edit.base] = spec;
      apply(edit);
    }
  }
}
