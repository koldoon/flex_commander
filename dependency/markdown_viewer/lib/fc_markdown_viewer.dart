/// Просмотрщик markdown: `F3` на `.md` показывает свёрстанный документ.
///
/// Модуль объявляет себя в общем реестре просмотрщиков и ничего не знает ни о
/// клавише, которой его открыли, ни о месте, куда поставили показ.
/// Спецификация — `docs/spec/markdown-viewer.md`.
library;

export 'src/markdown_sources.dart';
export 'src/markdown_viewer_commands.dart';
export 'src/markdown_viewer_module.dart';
export 'src/markdown_viewer_screen.dart';
export 'src/markdown_viewer_settings.dart';
export 'src/markdown_viewer_view.dart';
