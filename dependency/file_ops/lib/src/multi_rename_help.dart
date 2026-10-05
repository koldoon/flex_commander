import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Справка по маскам группового переименования (`docs/spec/multi-rename.md`,
/// §14).
///
/// Маски записаны как в Total Commander, и тот, кто там ими не пользовался, в
/// них не разберётся. Ответ — в самом окне: сначала рецепты, потом таблица.
///
/// Дочерним окном переименования: форма под ним остаётся с набранной маской.
void showMultiRenameHelp(Application app, {required String? parent}) {
  final view = app.view;
  late final String dialogId;
  dialogId = view.showDialog(
    DialogSpec(
      title: 'Rename mask help',
      id: helpDialogId,
      parent: parent,
      resizable: true,
      takesFocus: true,
      ownWidth: true,
      content: MultiRenameHelp(language: app.strings.language),
      onDismiss: () => view.closeDialog(dialogId),
    ),
  );
}

/// Имя окна справки: под ним помнится его размер.
const String helpDialogId = 'fileOps.multiRename.help';

/// Текст справки на языке приложения.
///
/// Два документа, а не ключ перевода: это не строка интерфейса, а текст, и
/// словарь с целыми страницами в ключах читать было бы нельзя.
String multiRenameHelpText(String language) => language == 'ru' ? _russian : _english;

/// Тело окна справки: свёрстанный документ тем же отрисовщиком, что и
/// просмотрщик `.md`.
class MultiRenameHelp extends StatefulWidget {
  const MultiRenameHelp({super.key, required this.language});

  final String language;

  @override
  State<MultiRenameHelp> createState() => _MultiRenameHelpState();
}

class _MultiRenameHelpState extends State<MultiRenameHelp> {
  late final FcMarkdownDocument _document = FcMarkdownDocument.parse(multiRenameHelpText(widget.language));

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final screen = MediaQuery.sizeOf(context);
    final stretches = FcDialogSizing.of(context);
    return SizedBox(
      // Ширину назначает само окно, долей экрана, — как и окно переименования.
      width: screen.width * metrics.dialogWidthFactor,
      // Высоту, пока её не задала рама, — тоже: документ длинный, а окно не
      // должно вырастать выше экрана.
      height: stretches ? null : screen.height * 0.6,
      child: FcMarkdownView(
        document: _document,
        autofocus: true,
        blockPadding: EdgeInsets.symmetric(vertical: metrics.dialogLineGap),
        // Поля окна — те же, что у заголовка и форм: текст стоит на одной
        // вертикали с названием окна.
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.dialogHorizontalPadding,
          vertical: metrics.dialogPadding,
        ),
        headingSpacing: metrics.dialogSectionGap * 2,
      ),
    );
  }
}

const String _english = '''
# Rename masks

The **Name** and **Extension** fields hold a *mask*: plain text is copied as
is, and anything in square brackets is replaced for every file. The preview
below the fields shows the result before you apply it.

## How to…

**Number the files** — put a counter where the number should go:

```
[N]_[C]          photo.jpg  →  photo_1.jpg, photo_2.jpg …
```

**Numbers with leading zeros** — the part after the colon is the width:

```
[N]_[C:3]        →  photo_001.jpg, photo_002.jpg …
```

**Start from another number, count by another step** — `[C10+5]` starts at
10 and adds 5 each time; the *Counter* fields of the window — *Start at*,
*Step by* and *Digits* — do the same for a plain `[C]`:

```
IMG_[C100+10:4]  →  IMG_0100.jpg, IMG_0110.jpg …
```

Files are numbered **in the order of the list** in the window.

**Put the date into the name** — the date each file was last modified:

```
[Y]-[M]-[D]_[N]  →  2026-10-05_photo.jpg
```

**Change the extension** — leave the name as `[N]` and write the new
extension into the *Extension* field, for example `txt`.

**Keep only part of the name** — take characters by position:

```
[N1-8]           first eight characters
[N3-]            everything from the third character
```

**Replace a part of every name** — use *Find* and *Replace with*. Tick
*Regular expression* to use groups: find `(\\d+)-(\\d+)`, replace with
`\$2-\$1`.

**Change the case** — *Name case* and *Extension case* are separate:
`.JPG` → `.jpg` without touching the name.

## Everything the mask understands

| Write | You get |
|---|---|
| `[N]` | the name without the extension |
| `[N5]` | the fifth character of the name |
| `[N2-5]` | characters 2 to 5 |
| `[N2,4]` | four characters from the second |
| `[N3-]` | from the third character to the end |
| `[N-3]` | the third character **from the end** |
| `[N2--2]` | from the second to the second from the end |
| `[E]`, `[E1-2]` | the extension, and the same cuts of it |
| `[C]` | the counter, by the fields of the window |
| `[C10]`, `[C10+5]`, `[C10+5:3]`, `[C:3]` | counter: start, step and digits right in the mask |
| `[Y]` `[M]` `[D]` | year (4 digits), month, day |
| `[h]` `[m]` `[s]` | hours, minutes, seconds |
| `[P]`, `[G]` | the name of the parent folder and of its parent |
| `[[` | a square bracket itself |

A cut beyond the end of a name gives nothing rather than an error, so one mask
works for names of any length. An unclosed bracket is an error: the mask is
underlined in red, and nothing is renamed until it is fixed.

## In what order

1. the name is split into the name and the extension (`archive.tar.gz` is
   `archive` and `tar.gz`);
2. both masks are applied;
3. they are joined with a dot (no dot if the extension is empty);
4. *Find → Replace with* runs over the whole result;
5. the case lists are applied.
''';

const String _russian = '''
# Маски переименования

В полях **Имя** и **Расширение** — *маска*: обычный текст переносится как
есть, а всё в квадратных скобках подставляется для каждого файла. Таблица под
полями показывает, что получится, ещё до применения.

## Как сделать

**Пронумеровать файлы** — поставить счётчик туда, где должен быть номер:

```
[N]_[C]          photo.jpg  →  photo_1.jpg, photo_2.jpg …
```

**Номера с нулями впереди** — после двоеточия ширина номера:

```
[N]_[C:3]        →  photo_001.jpg, photo_002.jpg …
```

**Начать с другого числа, считать с другим шагом** — `[C10+5]` начинает с 10
и прибавляет по 5; поля *Счётчик* в окне — *с*, *шаг* и *разрядов* — делают
то же для простого `[C]`:

```
IMG_[C100+10:4]  →  IMG_0100.jpg, IMG_0110.jpg …
```

Нумерация идёт **в порядке списка** в окне.

**Поставить дату в имя** — дата последнего изменения каждого файла:

```
[Y]-[M]-[D]_[N]  →  2026-10-05_photo.jpg
```

**Сменить расширение** — имя оставить `[N]`, а в поле *Расширение* написать
новое, например `txt`.

**Оставить часть имени** — взять знаки по номерам:

```
[N1-8]           первые восемь знаков
[N3-]            всё с третьего знака
```

**Заменить часть каждого имени** — поля *Найти* и *Заменить на*. С флажком
*Регулярное выражение* работают группы: найти `(\\d+)-(\\d+)`, заменить на
`\$2-\$1`.

**Сменить регистр** — списки *Регистр имени* и *Регистр расширения* свои:
`.JPG` → `.jpg`, не трогая имени.

## Всё, что понимает маска

| Запись | Что даёт |
|---|---|
| `[N]` | имя без расширения |
| `[N5]` | пятый знак имени |
| `[N2-5]` | знаки со второго по пятый |
| `[N2,4]` | четыре знака начиная со второго |
| `[N3-]` | с третьего знака до конца |
| `[N-3]` | третий знак **с конца** |
| `[N2--2]` | со второго по второй с конца |
| `[E]`, `[E1-2]` | расширение и те же срезы у него |
| `[C]` | счётчик по полям окна |
| `[C10]`, `[C10+5]`, `[C10+5:3]`, `[C:3]` | счётчик: начало, шаг и разрядность прямо в маске |
| `[Y]` `[M]` `[D]` | год (4 цифры), месяц, день |
| `[h]` `[m]` `[s]` | часы, минуты, секунды |
| `[P]`, `[G]` | имя родительской папки и папки над ней |
| `[[` | сама квадратная скобка |

Срез за концом имени даёт пустоту, а не ошибку — одна маска годится для имён
любой длины. Незакрытая скобка — ошибка: маска подчёркивается красным, и пока
её не исправить, ничего не переименуется.

## В каком порядке

1. имя делится на имя и расширение (`архив.tar.gz` — это `архив` и `tar.gz`);
2. применяются обе маски;
3. они склеиваются через точку (без точки, если расширение пустое);
4. *Найти → Заменить на* — по всему получившемуся имени;
5. списки регистра.
''';
