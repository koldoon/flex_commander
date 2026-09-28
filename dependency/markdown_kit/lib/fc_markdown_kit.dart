/// Показ markdown: оформление из темы, врезки кода и точка расширения.
///
/// Здесь то, чем показ markdown устроен одинаково везде: набор стилей, врезка
/// кода с подсветкой, разбор документа на блоки и сам ленивый показ. Библиотека,
/// а не модуль: регистрировать нечего, ею пользуются.
///
/// Отдельно от `fc_ui_kit`, потому что это не общий интерфейс приложения:
/// панелям и окнам разметка не нужна, а вместе с ней им достался бы
/// `flutter_markdown_plus`.
///
/// Объявление рисовальщика врезки (`MarkdownBlockSpec`) живёт **не здесь**, а в
/// `fc_ui_api`: объявляет его один модуль, а спрашивает другой, и пройти это
/// может только через реестр (`docs/spec/markdown-viewer.md`, §2.1).
library;

export 'src/markdown_code_block.dart';
export 'src/markdown_document.dart';
export 'src/markdown_fenced_builder.dart';
export 'src/markdown_strings.dart';
export 'src/markdown_style.dart';
export 'src/markdown_view.dart';
