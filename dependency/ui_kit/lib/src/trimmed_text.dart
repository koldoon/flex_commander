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

    return _wrapped(context, _plain(text), trimmed: !textFits(text, measured, width, scaler));
  }

  Widget _plain(String shown) => Text(
    shown,
    maxLines: 1,
    // Хвост режет `ellipsis`; голова уже отрезана — ей многоточие поставили мы.
    overflow: side == FcTrimSide.head ? TextOverflow.clip : TextOverflow.ellipsis,
    softWrap: false,
    textAlign: textAlign,
    style: style,
  );

  Widget _wrapped(BuildContext context, Widget shown, {required bool trimmed}) {
    // Выше уже договаривают — значит, о целом месте, а этот текст только его
    // часть: вложенные подсказки всплывали бы обе.
    if (!trimmed || FcTooltip.above(context)) {
      return shown;
    }
    return FcTooltip(message: text, child: shown);
  }
}
