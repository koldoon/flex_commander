"""Заметки о названном выпуске — тем же текстом, каким они написаны в
`docs/release-notes.md`.

Нужны выпуску на GitHub: его тело показывает не только страница релиза, но и
само приложение — в окне обновления (`docs/spec/self-update.md`, §3). Без
этого там оставалась одна строка «Full Changelog», сгенерированная GitHub, а
описание, написанное руками, никто не видел.

Заголовок раздела отбрасывается: имя выпуска и так стоит в заголовке окна и на
странице релиза, а повторять его третий раз незачем.

    python3 tool/release_notes.py v0.0.72
"""

import pathlib
import sys

tag = sys.argv[1] if len(sys.argv) > 1 else ''
lines = pathlib.Path('docs/release-notes.md').read_text().splitlines()

start = next((i for i, line in enumerate(lines) if line.startswith(f'## {tag} ')), None)
# Раздела нет — молчим: выпуск без описания это повод посмотреть глазами, а не
# повод остановить сборку.
if start is None:
    sys.exit(0)

end = next((i for i, line in enumerate(lines[start + 1 :], start + 1) if line.startswith('## v')), len(lines))
print('\n'.join(lines[start + 1 : end]).strip())
