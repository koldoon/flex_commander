# Иконка двухпанельного файлового менеджера — macOS 26

## Состав
- `FileManager.icon` — готовый пакет Icon Composer (фон, 2 группы, 6 слоёв, светлая и тёмная темы).
- `Layers/` — те же слои в SVG 1024×1024, все на своих местах; на случай ручной сборки.
- `Previews/` — PNG 1024 с эффектами: default, dark, clear (для сайта, App Store, README).
- `Legacy/AppIcon.icns` и `AppIcon.iconset` — растровая иконка для macOS 15 и старше или для сборки без Xcode 26.

## Быстрый путь (Xcode 26)
1. Откройте `FileManager.icon` в Icon Composer и проверьте режимы Default / Dark / Clear / Tinted.
2. Перетащите `FileManager.icon` в навигатор проекта.
3. Target → General → App Icon: впишите `FileManager` (имя файла без расширения).
   Старый AppIcon в Assets.xcassets можно удалить: для старых версий macOS Xcode сам сгенерирует растр.

## Если пакет не открылся — ручная сборка в Icon Composer
Холст 1024, маску, блики и тень не рисуйте: их добавляет система.

**Фон (Fill):** линейный градиент #5AAEFF → #1648C4. Для Dark: #3C3F47 → #131417.
Либо можно положить `background.svg` отдельным слоем.

**Группа Panels** (нижняя). Specular: вкл, Translucency: 40%, Shadow: Layer Color 50%.
| Слой | Цвет | Opacity light / dark |
|---|---|---|
| panel_left | #FFFFFF | 94% / 15% |
| panel_right | #FFFFFF | 74% / 9% |

**Группа Content** (верхняя). Specular: вкл, Translucency: выкл, Shadow: Neutral 30%.
Слои сверху вниз:
| Слой | Цвет light / dark | Opacity light / dark |
|---|---|---|
| selection_bar | #FFFFFF | 100% |
| selection | #1E63E8 | 100% |
| rows_left | #1648C4 / #FFFFFF | 26% / 34% |
| rows_right | #1648C4 / #FFFFFF | 22% / 24% |

## Проверка
- В Icon Composer переключите предпросмотр размеров: на 16 и 32 px должны читаться две панели и выделенная строка.
- Режим Tinted: выделение должно оставаться заметным. Если сливается, поднимите у selection значение Opacity в Tinted.
