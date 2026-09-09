import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Перетаскивание мышью — **дело панели, а не вида**.
///
/// Спецификация — `docs/spec/drag-and-drop.md`.
///
/// Жест не про то, чем нарисован каталог: тянут объект, бросают в каталог, и
/// оба раза речь о панели. Виду остаётся одно — сказать, что у него **вот
/// здесь**: строка это или пустое место, и какой прямоугольник подсветить.
/// Всё остальное — что поедет, чем это выполнить, как нарисовать рамку —
/// живёт тут, в одном месте на все виды.
///
/// Заведено это потому, что жеста не было нигде, кроме таблицы: дерево и
/// краткий вид про мышь не знали вовсе, а повторять в них сотню строк таблицы
/// значило бы завести три разных перетаскивания вместо одного.

/// Команды, которыми выполняется бросок.
///
/// Идентификаторами, а не классами: работа живёт в модуле файловых операций, а
/// приложение обязано собираться без него — тогда бросок просто ничего не
/// сделает.
const String dropCopyCommandId = 'file.copy';
const String dropMoveCommandId = 'file.move';

/// Доводы тех же команд: что переносим и куда.
const String dropSourcesParam = 'sources';
const String dropDestinationParam = 'destination';

/// Что поедет, если потянуть за эту строку.
///
/// Тянут помеченное — едет вся пометка; тянут непомеченную строку — едет она
/// одна, и пометка не трогается вовсе. Правило всех коммандеров, и оно же
/// единственное, которое не удивляет: человек видит, что схватил.
///
/// Обещанием: помеченное бывает и в соседних ветвях дерева, а значений их строк
/// по эту сторону нет — тогда за ними идут в ядро
/// (`docs/spec/operation-targets.md`, §4). Когда всё помеченное на виду — а это
/// обычный случай, — границу никто не трогает.
Future<List<FileEntry>> dragEntriesOf(Session panel, FileEntry entry) async {
  if (!panel.isMarked(entry)) {
    return [entry];
  }
  final seen = panel.targets;
  // Считается по путям, и разойтись они не могут: `targets` — ровно те строки
  // списка, чей путь помечен.
  if (seen.length == panel.targetPaths.length) {
    return seen;
  }
  return panel.allTargets();
}

/// Обернуть строку источником перетаскивания.
///
/// Нет службы — нет и жеста: строка возвращается как была
/// (`docs/spec/drag-and-drop.md`, §3).
Widget panelDragSource({
  required BuildContext context,
  required Session panel,
  required FileEntry entry,
  required Widget child,
}) {
  // «..» источником не бывает: это не объект, а способ выйти наверх.
  if (entry.isParent) {
    return child;
  }
  final dnd = AppScope.read(context).dragAndDrop;
  return dnd == null ? child : dnd.source(owner: panel, child: child, entries: () => dragEntriesOf(panel, entry));
}

/// Область панели, принимающая брошенное.
///
/// [spotAt] отвечает, что у вида под точкой — в его местных координатах;
/// [highlightOf] говорит, какой прямоугольник обвести, а `null` от него значит
/// «вся область» (бросили мимо строк).
///
/// **Слой подсветки стоит всегда**, а подсветка живёт внутри него рисунком:
/// строение дерева виджетов посреди жеста меняться не вправе. На этом уже
/// погорели однажды — список перематывался к началу, стоило указателю пройти
/// над своим же окном (`docs/spec/drag-and-drop.md`, §10).
class PanelDropArea extends StatelessWidget {
  const PanelDropArea({
    super.key,
    required this.panel,
    required this.spotAt,
    required this.highlightOf,
    required this.child,
    this.onDropped,
  });

  final Session panel;

  /// Что у вида под точкой; null — сюда нельзя, и подсветки не будет.
  final DropSpot? Function(Offset local) spotAt;

  /// Прямоугольник подсветки в местных координатах; null — вся область.
  ///
  /// Ширина `double.infinity` значит «во всю ширину области»: строка списка
  /// тянется от края до края, и мерить её виду незачем.
  final Rect? Function(DropSpot spot) highlightOf;

  /// Бросок состоялся. Виду бывает что доделать: дерево, например, раскрывает
  /// каталог, в который бросили.
  final void Function(DropSpot spot)? onDropped;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final dnd = app.dragAndDrop;
    if (dnd == null) {
      // Перетаскивания может не быть вовсе — тогда вид такой же, как был:
      // панель про мышь снаружи ничего не знает.
      return child;
    }

    final theme = FcTheme.of(context);
    return dnd.target(
      // Хозяин места — сама панель: из неё тащат, в неё бросают, и в себя же
      // бросать нельзя.
      owner: panel,
      spotAt: spotAt,
      onDrop: (spot, payload) async {
        await runDrop(app, panel, spot, payload);
        onDropped?.call(spot);
      },
      builder: (context, hovered) {
        final rect = hovered == null ? null : highlightOf(hovered);
        return Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DropHighlightPainter(
                    rect: rect,
                    whole: hovered != null && rect == null,
                    color: theme.colors.cursorBackground,
                    width: theme.metrics.strokeWidth * 2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Брошенное идёт теми же командами, что работают за `F5` и `F6`.
///
/// С `Shift` — перенос, без него — копия: так принято везде, и решает это
/// система, а не мы (она же и значок у курсора рисует).
Future<void> runDrop(Application app, Session panel, DropSpot spot, DropPayload payload) async {
  if (payload.paths.isEmpty) {
    return;
  }
  // Бросок делает панель активной — как и щелчок по ней: работа пойдёт **в
  // неё**, и человек должен видеть, где он теперь.
  app.activate(panel);
  app.commands.run(
    payload.moves ? dropMoveCommandId : dropCopyCommandId,
    CommandInvocation(parameters: {dropSourcesParam: payload.paths, dropDestinationParam: spot.destination}),
  );
}

/// Рамка вокруг того, куда попадёт брошенное.
class DropHighlightPainter extends CustomPainter {
  const DropHighlightPainter({required this.rect, required this.whole, required this.color, required this.width});

  /// Что обвести; null — либо вся область ([whole]), либо ничего.
  ///
  /// Бесконечная ширина означает «до правого края»: строка занимает всю ширину,
  /// а сколько это в точках, знает только холст.
  final Rect? rect;

  /// Подсвечивается вся область: бросили мимо строк.
  final bool whole;

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    var target = whole ? Offset.zero & size : rect;
    if (target == null) {
      return;
    }
    if (target.width.isInfinite) {
      target = Rect.fromLTWH(target.left, target.top, size.width - target.left, target.height);
    }
    canvas.drawRect(
      target.deflate(width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(DropHighlightPainter old) =>
      old.rect != rect || old.whole != whole || old.color != color || old.width != width;
}
