#!/usr/bin/env python3
"""Сверка макета с эталонами — числами, а не глазами.

Каждое окно приложения снято настоящими шрифтами в `test/view/goldens`
(`anchor_*.png`), и тот же символ выгружен из `docs/design/design.sketch`
в PNG 1:1. Скрипт находит окно в эталоне, разбирает оба снимка на **полосы
чернил** — начало и конец каждой строки, — сводит их по ближайшему верху и
показывает всё, что разошлось больше чем на точку.

Полосами, а не попиксельно: набор в Sketch и во Flutter отличается шириной
примерно на три процента, и попиксельное сравнение утонуло бы в этом. Верх
полосы и её левый край от набора не зависят — по ним и сверяемся.

Выгрузка делается вручную, через Sketch MCP:

    sketch.export(instance, { output: DIR, formats: 'png', scales: '1',
                              overwriting: true, 'use-id-for-name': true })

Запуск:  python3 tool/design_sweep.py <каталог с выгрузкой> [имя окна]
"""

import os
import sys

from PIL import Image

GOLD = os.path.join(os.path.dirname(__file__), '..', 'test', 'view', 'goldens')

# Роли фона: `dialog/background` и `dialog/title-background`.
DIALOG = (1, 30, 55)
TITLE = (4, 52, 91)

# Окно, его эталон и идентификатор экземпляра в макете.
WINDOWS = [
    ('Copy', 'anchor_copy.png', '67AD63B7-8C83-423F-833B-FA6936ECB03D'),
    ('Move', 'anchor_move.png', '7D7C1E25-8123-4818-8734-68EF5F5B67AB'),
    ('Make Archive', 'anchor_archive.png', '3DC18FD1-68BA-4E63-AEAB-C78A5D49272F'),
    ('Find Files', 'anchor_find.png', '6BEFFACC-50ED-44A3-88F0-51EF25479295'),
    ('Find Results', 'anchor_find_results.png', 'AEBA1C50-87AE-438E-BBB1-05123CB89CCB'),
    ('Help', 'anchor_help.png', '7AC5BD33-53CD-450A-B9BE-BE47B31DFA3E'),
    ('Settings', 'anchor_settings.png', '846421CB-13F0-41F3-ADD6-B893499B6D0E'),
    ('Panel View', 'anchor_view.png', '6A0FB066-0F88-44FB-8BEE-175A6790AD1A'),
    ('View Brief', 'anchor_view_brief.png', 'E0148491-23B5-430B-B5F7-341D712B7B65'),
    ('View Tree', 'anchor_view_tree.png', '4D4819F3-A936-4608-970C-4636FC0BF065'),
]

# Полоса заголовка у всех окон одна и та же; сверять её незачем, а её нижняя
# грань даёт лишнюю полосу, которая сбивала бы сведение.
SKIP_TOP = 38


def window_rect(image):
    """Прямоугольник окна: строки и столбцы, плотно занятые его фоном."""
    pixels = image.load()
    width, height = image.size
    rows = [y for y in range(height)
            if sum(1 for x in range(width) if pixels[x, y] in (DIALOG, TITLE)) > 150]
    columns = [x for x in range(width)
               if sum(1 for y in range(height) if pixels[x, y] in (DIALOG, TITLE)) > 60]
    return min(columns), min(rows), max(columns) + 1, max(rows) + 1


def ink_bands(image, rect):
    """Полосы чернил внутри окна: [верх, низ, слева, справа]."""
    pixels = image.load()
    bands, current = [], None
    for y in range(rect[1] + SKIP_TOP, rect[3]):
        ink = [x for x in range(rect[0], rect[2]) if pixels[x, y] != DIALOG]
        if ink:
            top, left, right = y - rect[1], min(ink) - rect[0], max(ink) - rect[0]
            if current is None:
                current = [top, top, left, right]
            else:
                current[1] = top
                current[2] = min(current[2], left)
                current[3] = max(current[3], right)
        elif current:
            bands.append(current)
            current = None
    if current:
        bands.append(current)
    return bands


def compare(name, gold_file, mock_file):
    gold = Image.open(os.path.join(GOLD, gold_file)).convert('RGB')
    mock = Image.open(mock_file).convert('RGB')
    gold_rect, mock_rect = window_rect(gold), window_rect(mock)
    gold_size = (gold_rect[2] - gold_rect[0], gold_rect[3] - gold_rect[1])
    mock_size = (mock_rect[2] - mock_rect[0], mock_rect[3] - mock_rect[1])
    verdict = 'ok' if all(abs(a - b) <= 1 for a, b in zip(gold_size, mock_size)) else 'ОТЛИЧАЕТСЯ'

    gold_bands = ink_bands(gold, gold_rect)
    mock_bands = ink_bands(mock, mock_rect)

    # Сводим по ближайшему верху, а не по номеру: соседние строки то сливаются
    # в одну полосу, то нет, и нумерация от этого разъезжается.
    taken, issues = set(), []
    for band in gold_bands:
        best = None
        for i, other in enumerate(mock_bands):
            if i in taken:
                continue
            distance = abs(other[0] - band[0])
            if distance <= 6 and (best is None or distance < best[0]):
                best = (distance, i, other)
        if best is None:
            issues.append('   в эталоне %s — в макете такой полосы нет' % band)
            continue
        taken.add(best[1])
        top, left = best[2][0] - band[0], best[2][2] - band[2]
        if abs(top) > 1 or abs(left) > 1:
            issues.append('   макет %-22s эталон %-22s   верх %+d слева %+d'
                          % (best[2], band, top, left))
    for i, band in enumerate(mock_bands):
        if i not in taken:
            issues.append('   в макете %s — в эталоне такой полосы нет' % band)

    print('== %-18s макет %dx%d / эталон %dx%d  [%s]  полос %d / %d'
          % (name, mock_size[0], mock_size[1], gold_size[0], gold_size[1],
             verdict, len(mock_bands), len(gold_bands)))
    print('\n'.join(issues) if issues else '   все полосы сошлись в пределах точки')
    print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    exported = sys.argv[1]
    only = sys.argv[2].lower() if len(sys.argv) > 2 else None
    for name, gold_file, layer_id in WINDOWS:
        if only and only not in name.lower():
            continue
        mock_file = os.path.join(exported, layer_id + '.png')
        if not os.path.exists(mock_file):
            print('== %-18s выгрузки нет (%s.png)' % (name, layer_id))
            continue
        compare(name, gold_file, mock_file)
    return 0


if __name__ == '__main__':
    sys.exit(main())
