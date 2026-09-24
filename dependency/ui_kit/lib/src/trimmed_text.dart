import 'package:flutter/widgets.dart';

import 'fc_theme.dart';
import 'fc_tooltip.dart';
import 'text_trim.dart';

/// С какой стороны резать то, что не поместилось.
enum FcTrimSide {
  /// Хвост — имена: читаются с начала, и начало важнее.
  tail,

  /// Голова — пути: в конце текущий каталог, а по началу видно, о каком корне
  /// речь ([trimTextHead]).
  head,

  /// Середина — имена, когда так попросили: видны оба конца, и расширение в
  /// том числе ([trimTextMiddle], `docs/spec/name-trim.md`).
  ///
  /// Не про пути: у них середины не режут — звено с дырой посередине читается
  /// как другое имя.
  middle,
}

/// Строка, которой может не хватить ширины: обрежется — и договорится
/// подсказкой.
///
/// Один виджет на всё приложение (`docs/spec/tooltips.md`, §3). Иначе
/// «дочитать обрезанное» было бы заведено в таблице, в дереве и в находках
/// трижды и по-разному — ровно то, от чего спасает общее правило обрезки пути.
///
/// **Подсказка появляется только у обрезанного.** Всплывающая над каждой
/// строкой подсказка мешает читать список и перекрывает соседние строки;
/// поместившийся текст не заводит её вовсе — не «заводит пустую».
///
/// **Рисование при этом не меняется ни на точку**: многоточие по-прежнему
/// ставит `TextOverflow.ellipsis`, а не мы. Ручная обрезка встала бы на другой
/// границе знака, и поехали бы эталонные снимки; меряем только ради ответа
/// «да/нет». Зато и проверка честна: подсказка появляется ровно тогда, когда
/// многоточие и правда сработало.
class FcTrimmedText extends StatelessWidget {
  const FcTrimmedText({
    super.key,
    required this.text,
    required this.style,
    this.width,
    this.side = FcTrimSide.tail,
    this.textAlign = TextAlign.start,
    this.hugged = false,
    this.maxLines = 1,
  });

  final String text;

  final TextStyle style;

  /// Сколько места отведено; null — столько, сколько дадут.
  ///
  /// Числом — там, где место делят с кем-то ещё и знают, сколько отняли: ячейка
  /// таблицы, ячейка заголовка, плашка со слотом. В ленивом списке это
  /// единственный приемлемый вариант: своя раскладка на каждую ячейку отнимает
  /// дешевизну постоянной высоты строки (`docs/widgets.md`, §4). Пусто — там,
  /// где текст занимает всё оставшееся (`Expanded` в дереве, имя находки):
  /// арифметика из семи слагаемых была бы хрупкой.
  final double? width;

  final FcTrimSide side;

  final TextAlign textAlign;

  /// Окно облегает содержимое — мерить нечем и незачем.
  ///
  /// Спрашивать ширину у раскладки в таком окне нельзя: рама меряет содержимое
  /// интринсиками, а `LayoutBuilder` на этот вопрос отвечать не умеет
  /// (`docs/spec/dialog-body.md`). Да и незачем: окно ровно такой ширины, какой
  /// хватило, и текст в нём не режется никогда. Сказано параметром, а не
  /// молчанием: забыл поставить — прогон падает, а не показывает не то.
  final bool hugged;

  /// Сколько строк текст вправе занять.
  ///
  /// Больше одной — там, где место под них отведено заранее и высота от этого
  /// не скачет: имя под значком в сетке занимает две строки всегда, влезло оно
  /// в одну или нет (`docs/spec/panel-view-icons.md`, §4). Обрезка и подсказка
  /// считаются по **последней** строке: не влез — договаривает подсказка.
  ///
  /// Обрезка слева (сторона [FcTrimSide.head]) многострочной не бывает: путь
  /// режут ради одной строки, и разложить его по двум значило бы не решить
  /// задачу, а отложить.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (hugged || text.isEmpty) {
      return _plain(text);
    }
    if (width case final width?) {
      return _measured(context, width);
    }
    return LayoutBuilder(builder: (context, constraints) => _measured(context, constraints.maxWidth));
  }

  Widget _measured(BuildContext context, double width) {
    // Тем же стилем, каким будет набрано: мерить не то, что рисуется, значит
    // ошибиться на разрядку окружения ([FcTheme.effective]).
    final measured = FcTheme.effective(context, style);
    final scaler = MediaQuery.textScalerOf(context);

    if (side == FcTrimSide.head) {
      final shown = trimTextHead(text, measured, width, scaler);
      return _wrapped(context, _plain(shown), trimmed: shown != text);
    }

    if (side == FcTrimSide.middle) {
      // Имя сокращается **целиком**, сколько бы строк ему ни отвели: дыра в
      // середине имени одна, а не по одной на строку.
      final shown = trimTextMiddle(text, measured, width, scaler, maxLines: maxLines);
      return _wrapped(context, _plain(shown), trimmed: shown != text);
    }

    if (maxLines > 1) {
      // Несколько строк — и мерка другая: помещается ли текст в отведённые
      // строки, а не в одну. Ту же меру завела многострочная строка состояния.
      final fits = spanFitsLines(TextSpan(text: text, style: measured), width, scaler, maxLines: maxLines);
      return _wrapped(context, _plain(text), trimmed: !fits);
    }

    return _wrapped(context, _plain(text), trimmed: !textFits(text, measured, width, scaler));
  }

  Widget _plain(String shown) => Text(
    shown,
    maxLines: maxLines,
    // Хвост режет `ellipsis`; голову и середину отрезали мы, и многоточие в
    // них уже стоит — второе поставил бы `ellipsis`.
    overflow: side == FcTrimSide.tail ? TextOverflow.ellipsis : TextOverflow.clip,
    // Переносим только там, где строк больше одной: у однострочного переносить
    // нечего, а `softWrap: false` бережёт раскладку от лишней работы.
    softWrap: maxLines > 1,
    textAlign: textAlign,
    style: style,
  );

  Widget _wrapped(BuildContext context, Widget shown, {required bool trimmed}) =>
      fcTooltipIf(context, trimmed: trimmed, message: text, child: shown);
}

/// Подсказка, если текст обрезан, — и ничего, если поместился.
///
/// Отдельной функцией: тем же правилом живут строки списка, где текст набран
/// не одной строкой, а кусками разного цвета ([FcPickList]), — а два места,
/// решающих одно, однажды разойдутся.
///
/// Подсказка **выше по дереву отменяет свою**: та говорит о целом месте (плашка
/// пути — о всей плашке, включая крошки, которые роняют звенья), а этот текст
/// только его часть. Вложенные всплывали бы обе: наведение приходит всем, кто
/// под курсором.
Widget fcTooltipIf(BuildContext context, {required bool trimmed, required String message, required Widget child}) {
  if (!trimmed || FcTooltip.above(context)) {
    return child;
  }
  return FcTooltip(message: message, child: child);
}
