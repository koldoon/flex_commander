import 'dart:ui';

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замер с постоянной шириной знака: координаты становятся точными числами, и
/// утверждения — осмысленными (`docs/spec/mermaid.md`, §4).
class _FakeMeasure implements DiagramTextMeasure {
  const _FakeMeasure();

  static const double charWidth = 7;
  static const double lineHeight = 16;

  @override
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth = double.infinity}) {
    final lines = text.split('\n');
    final widest = lines.map((line) => line.length).fold(0, (a, b) => a > b ? a : b);

    return _FakeRun(Size(widest * charWidth, lines.length * lineHeight));
  }
}

class _FakeRun implements DiagramTextRun {
  const _FakeRun(this.size);

  @override
  final Size size;

  @override
  void paint(Canvas canvas, Offset at) {}
}

void main() {
  const measure = _FakeMeasure();

  DiagramLayout layout(String body) => layoutSequence(parseSequenceDiagram('sequenceDiagram\n$body'), measure);

  List<DiagramPath> pathsOf(DiagramLayout l) => l.shapes.whereType<DiagramPath>().toList();
  List<DiagramBox> boxesOf(DiagramLayout l) => l.shapes.whereType<DiagramBox>().toList();
  List<DiagramLabel> labelsOf(DiagramLayout l) => l.shapes.whereType<DiagramLabel>().toList();

  /// Стрелки сообщений: прямые, не пунктирные линии жизни и не черты рамок.
  List<DiagramPath> arrowsOf(DiagramLayout l) => pathsOf(l).where((p) => p.head != DiagramHead.none).toList();

  group('столбцы', () {
    test('шапки не налезают друг на друга', () {
      final l = layout('participant Один\nparticipant Два\nparticipant Три\nОдин->>Три: раз\n');
      final headers = boxesOf(l).where((b) => b.ink == DiagramInk.plate).toList();

      for (var i = 0; i + 1 < headers.length; i++) {
        expect(headers[i].rect.right, lessThanOrEqualTo(headers[i + 1].rect.left), reason: 'столбцы $i и ${i + 1}');
      }
    });

    test('длинная подпись раздвигает столбцы', () {
      final narrow = layout('A->>B: ок\n');
      final wide = layout('A->>B: очень длинная подпись сообщения на весь экран\n');

      expect(wide.size.width, greaterThan(narrow.size.width));

      // Расстояние между линиями жизни не меньше подписи.
      final arrow = arrowsOf(wide).single;
      final label = labelsOf(wide).firstWhere((x) => x.run.size.width > 100);
      expect((arrow.points.last.dx - arrow.points.first.dx).abs(), greaterThanOrEqualTo(label.run.size.width));
    });

    test('всё умещается в объявленный размер', () {
      final l = layout(
        'participant A\nparticipant B\nA->>B: раз\nNote over A,B: заметка\nalt да\n  B-->>A: два\nend\n',
      );

      for (final shape in l.shapes) {
        switch (shape) {
          case DiagramBox(:final rect):
            expect(rect.right, lessThanOrEqualTo(l.size.width + 0.01), reason: 'коробка вылезла вправо');
            expect(rect.bottom, lessThanOrEqualTo(l.size.height + 0.01), reason: 'коробка вылезла вниз');
          case DiagramPath(:final points):
            for (final p in points) {
              expect(p.dx, lessThanOrEqualTo(l.size.width + 0.01));
              expect(p.dy, lessThanOrEqualTo(l.size.height + 0.01));
            }
          case DiagramLabel(:final at, :final run):
            expect(at.dx + run.size.width, lessThanOrEqualTo(l.size.width + 0.01));
            expect(at.dy + run.size.height, lessThanOrEqualTo(l.size.height + 0.01));
          case DiagramFigure(:final path):
            // Фигур последовательность не рисует: они из графа.
            expect(path, isNotNull);
        }
      }
    });
  });

  group('вертикаль', () {
    test('сообщения идут сверху вниз в порядке записи', () {
      final l = layout('A->>B: раз\nB-->>A: два\nA->>B: три\n');
      final ys = arrowsOf(l).map((p) => p.points.first.dy).toList();

      expect(ys, hasLength(3));
      for (var i = 0; i + 1 < ys.length; i++) {
        expect(ys[i], lessThan(ys[i + 1]), reason: 'шаг $i должен быть выше следующего');
      }
    });

    test('подпись стоит над своей стрелкой, а не под ней', () {
      final l = layout('A->>B: подпись\n');
      final arrow = arrowsOf(l).single;
      final label = labelsOf(l).firstWhere((x) => x.run.size.width == 'подпись'.length * 7);

      expect(label.at.dy, lessThan(arrow.points.first.dy));
    });

    test('линии жизни идут от шапок до низа', () {
      final l = layout('A->>B: раз\n');
      final lifelines = pathsOf(l).where((p) => p.dashed && p.points.first.dx == p.points.last.dx).toList();

      expect(lifelines, hasLength(2));
      for (final line in lifelines) {
        expect(line.points.first.dy, lessThan(line.points.last.dy));
        expect(line.points.last.dy, greaterThanOrEqualTo(arrowsOf(l).single.points.first.dy));
      }
    });
  });

  group('рамки', () {
    test('рамка покрывает свои шаги и не покрывает соседние', () {
      final l = layout('A->>B: до\nalt да\n  A->>B: внутри\nend\nA->>B: после\n');
      final frame = boxesOf(l).firstWhere((b) => !b.filled);
      final arrows = arrowsOf(l);

      expect(arrows, hasLength(3));
      expect(arrows[0].points.first.dy, lessThan(frame.rect.top), reason: 'то, что до, — выше рамки');
      expect(arrows[1].points.first.dy, greaterThan(frame.rect.top));
      expect(arrows[1].points.first.dy, lessThan(frame.rect.bottom), reason: 'внутреннее — внутри');
      expect(arrows[2].points.first.dy, greaterThan(frame.rect.bottom), reason: 'то, что после, — ниже');
    });

    test('вложенная рамка лежит внутри внешней', () {
      final l = layout('alt внешнее\n  alt внутреннее\n    A->>B: раз\n  end\nend\n');
      final frames = boxesOf(l).where((b) => !b.filled).toList();

      expect(frames, hasLength(2));
      final outer = frames.reduce((a, b) => a.rect.height >= b.rect.height ? a : b);
      final inner = frames.firstWhere((f) => f != outer);

      expect(outer.rect.top, lessThanOrEqualTo(inner.rect.top));
      expect(outer.rect.bottom, greaterThanOrEqualTo(inner.rect.bottom));
      expect(outer.rect.left, lessThanOrEqualTo(inner.rect.left));
      expect(outer.rect.right, greaterThanOrEqualTo(inner.rect.right));
    });

    test('черта между ветвями есть у каждой рамки, включая внешнюю', () {
      // Список ожидающих черт был общим на все уровни: вложенная рамка
      // патчила и запись внешней, и черта внешней получала чужую ширину.
      final l = layout(
        'alt внешнее да\n'
        '  A->>B: раз\n'
        'else внешнее нет\n'
        '  alt внутреннее да\n'
        '    A->>B: два\n'
        '  else внутреннее нет\n'
        '    A->>B: три\n'
        '  end\n'
        'end\n',
      );

      final dividers = pathsOf(l).where((p) => p.dashed && p.points.first.dy == p.points.last.dy).toList();
      final widths = dividers.map((p) => p.points.last.dx - p.points.first.dx).toSet();

      expect(dividers, hasLength(2), reason: 'по черте на каждую рамку с `else`');
      // Внешняя рамка шире вложенной, значит и черты у них разной длины. С
      // общим списком обе получали ширину вложенной — и выглядело это
      // правдоподобно, потому и не ловилось проверкой «длина больше нуля».
      expect(widths, hasLength(2), reason: 'черта внешней рамки взяла чужие края');

      final frames = boxesOf(l).where((b) => !b.filled).toList();
      final outer = frames.reduce((a, b) => a.rect.width >= b.rect.width ? a : b);
      expect(widths.reduce((a, b) => a > b ? a : b), outer.rect.width, reason: 'широкая черта — по внешней рамке');
    });

    test('ярлык ветви написан словом рамки', () {
      final l = layout('alt да\n  A->>B: раз\nelse нет\n  A->>B: два\nend\n');
      final texts = labelsOf(l).map((x) => x.run.size.width).toList();

      // Точного текста подставной замер не несёт — проверяем, что ярлыков
      // ровно два и они разной длины: «alt да» и «else нет».
      expect(texts.where((w) => w == 'alt да'.length * 7), hasLength(1));
      expect(texts.where((w) => w == 'else нет'.length * 7), hasLength(1));
    });
  });

  group('активность', () {
    test('полоса идёт от `activate` до `deactivate`', () {
      final l = layout('A->>B: раз\nactivate B\nB-->>A: два\ndeactivate B\nA->>B: три\n');
      final bars = boxesOf(l).where((b) => b.ink == DiagramInk.bar).toList();

      expect(bars, hasLength(1));
      final arrows = arrowsOf(l);
      expect(bars.single.rect.top, greaterThanOrEqualTo(arrows[0].points.first.dy));
      expect(bars.single.rect.bottom, lessThanOrEqualTo(arrows[2].points.first.dy));
    });

    test('краткие `+` и `-` делают то же самое', () {
      final l = layout('A->>+B: раз\nB-->>-A: два\n');

      expect(boxesOf(l).where((b) => b.ink == DiagramInk.bar), hasLength(1));
    });

    test('незакрытая полоса доходит до низа, а не роняет раскладку', () {
      final l = layout('A->>B: раз\nactivate B\nB-->>A: два\n');
      final bar = boxesOf(l).firstWhere((b) => b.ink == DiagramInk.bar);

      expect(bar.rect.bottom, greaterThanOrEqualTo(arrowsOf(l).last.points.first.dy));
      expect(bar.rect.bottom, lessThanOrEqualTo(l.size.height));
    });
  });

  group('плашки участников', () {
    test('плашка залита своей краской, а не как коробка заметки', () {
      // Она инвертирована: заливка цветом линий, надпись цветом фона.
      final l = layout('participant A\nNote over A: заметка\n');

      expect(boxesOf(l).where((b) => b.ink == DiagramInk.plate), hasLength(1));
      expect(boxesOf(l).where((b) => b.ink == DiagramInk.fill), hasLength(1));
    });
  });

  group('надписи поверх линий', () {
    test('подпись сообщения просит подложку, а надпись на плашке — нет', () {
      // Подпись сидит ровно на линиях жизни: без подложки буквы в них тонут.
      // Плашке подложка не нужна — она сама себе фон.
      final l = layout('participant A\nA->>B: раз\n');
      final backed = labelsOf(l).where((label) => label.backdrop).toList();

      expect(backed, hasLength(1), reason: 'подпись сообщения — одна');
      expect(labelsOf(l).where((label) => !label.backdrop), isNotEmpty, reason: 'надписи на плашках');
    });

    test('ярлык рамки тоже с подложкой', () {
      final l = layout('alt да\n  A->>B: раз\nend\n');

      expect(labelsOf(l).where((label) => label.backdrop), hasLength(2), reason: 'ярлык рамки и подпись сообщения');
    });

    test('ни одна подложка не накрывает горизонтальную черту', () {
      // Подложка ярлыка выедала из верха рамки и из границы между ветвями по
      // куску: ярлык сидел ровно на черте. А черта здесь граница — её видно
      // должно быть целиком.
      final l = layout('alt да\n  A->>B: раз\nelse нет\n  A->>B: два\nend\n');
      final frame = boxesOf(l).firstWhere((b) => b.ink == DiagramInk.faint && !b.filled);
      final lines = [
        frame.rect.top,
        frame.rect.bottom,
        ...pathsOf(l).where((p) => p.points.first.dy == p.points.last.dy).map((p) => p.points.first.dy),
      ];

      for (final label in labelsOf(l).where((label) => label.backdrop)) {
        // Подложка шире надписи на пиксель сверху и снизу — иначе линия
        // просвечивает вплотную к буквам.
        final top = label.at.dy - 1;
        final bottom = label.at.dy + label.run.size.height + 1;

        for (final line in lines) {
          expect(line > top && line < bottom, isFalse, reason: 'черта на $line попала под подложку $top…$bottom');
        }
      }
    });

    test('рамка ложится раньше надписей', () {
      // Порядок фигур — порядок отрисовки. Рисуй рамку последней, её черта
      // прошла бы поверх подписи, и подложка ничего бы не спасла.
      final l = layout('alt да\n  A->>B: раз\nend\n');
      final frame = l.shapes.indexWhere((s) => s is DiagramBox && s.ink == DiagramInk.faint && !s.filled);
      final label = l.shapes.indexWhere((s) => s is DiagramLabel && s.backdrop);

      expect(frame, isNonNegative, reason: 'черта рамки должна найтись');
      expect(frame, lessThan(label));
    });
  });

  group('особые случаи', () {
    test('сообщение самому себе рисуется петлёй вправо', () {
      final l = layout('A->>A: сам себе\n');
      final loop = arrowsOf(l).single;

      expect(loop.points, hasLength(4));
      final lifeline = loop.points.first.dx;
      expect(loop.points[1].dx, greaterThan(lifeline), reason: 'петля уходит вправо');
      expect(loop.points.last.dx, lifeline, reason: 'и возвращается на ту же линию');
    });

    test('заметка поверх двоих стоит между ними', () {
      final l = layout('participant A\nparticipant B\nNote over A,B: общая\n');
      final note = boxesOf(l).firstWhere((b) => b.ink == DiagramInk.fill);
      final headers = boxesOf(l).where((b) => b.ink == DiagramInk.plate).toList();

      expect(note.rect.center.dx, greaterThan(headers.first.rect.center.dx));
      expect(note.rect.center.dx, lessThan(headers.last.rect.center.dx));
    });

    test('пунктир у сообщения виден в фигуре', () {
      expect(arrowsOf(layout('A-->>B: раз\n')).single.dashed, isTrue);
      expect(arrowsOf(layout('A->>B: раз\n')).single.dashed, isFalse);
    });

    test('наконечники разные', () {
      expect(arrowsOf(layout('A-xB: раз\n')).single.head, DiagramHead.cross);
      expect(arrowsOf(layout('A-)B: раз\n')).single.head, DiagramHead.open);
    });

    test('нумерация приписывает номера по порядку', () {
      final numbered = layout('autonumber\nA->>B: раз\nA->>B: два\n');
      final plain = layout('A->>B: раз\nA->>B: два\n');

      // «1. раз» длиннее «раз» ровно на три знака — приписку видно по ширине.
      double widest(DiagramLayout l) => labelsOf(l).map((x) => x.run.size.width).reduce((a, b) => a > b ? a : b);

      expect(widest(numbered) - widest(plain), 3 * 7);
    });

    test('диаграмма без участников — пустая раскладка, а не падение', () {
      expect(layoutSequence(const SequenceDiagram(participants: [], steps: []), measure), DiagramLayout.empty);
    });
  });

  group('пример из задачи', () {
    const source = '''
sequenceDiagram
    autonumber
    participant Cli as Client
    participant API as Cloud API
    participant T as Терминал локации
    participant CSO as CSO (учётная система)

    Cli->>API: POST /locations/{id}/orders
    API-->>Cli: 200 { order_id } — order_number ещё 0

    alt order_number передан клиентом
        API->>CSO: выгрузка заказа
    else order_number == 0
        alt нумерация от терминала локации (режим по умолчанию)
            API->>T: запрос номера и UPC
            T-->>API: { order_number, upc } — таймаут 20 с
        else внутренняя нумерация
            API->>API: счётчик локации 100…999
        end
        API->>CSO: выгрузка заказа
    end

    CSO-->>API: подтверждение приёма
    loop опрос клиента
        Cli->>API: GET /locations/{id}/orders/{order_id}
        API-->>Cli: заказ { order_number, processstatus, paymentstatus }
    end
''';

    test('раскладывается и даёт непустую картинку', () {
      final l = layoutSequence(parseSequenceDiagram(source), measure);

      expect(l.size.width, greaterThan(0));
      expect(l.size.height, greaterThan(0));
      expect(l.shapes, isNotEmpty);
    });

    test('все десять сообщений на месте и идут сверху вниз', () {
      final l = layoutSequence(parseSequenceDiagram(source), measure);
      final ys = arrowsOf(l).map((p) => p.points.first.dy).toList();

      // Десять: два вначале, одно в первой ветви, три во вложенной, одно после
      // неё, подтверждение и два в цикле.
      expect(ys, hasLength(10));
      for (var i = 0; i + 1 < ys.length; i++) {
        expect(ys[i], lessThan(ys[i + 1]));
      }
    });

    test('три рамки: внешняя, вложенная и цикл', () {
      final l = layoutSequence(parseSequenceDiagram(source), measure);

      expect(boxesOf(l).where((b) => !b.filled), hasLength(3));
    });

    test('ничего не вылезает за размер', () {
      final l = layoutSequence(parseSequenceDiagram(source), measure);

      for (final shape in l.shapes) {
        if (shape case DiagramPath(:final points)) {
          for (final p in points) {
            expect(p.dx, lessThanOrEqualTo(l.size.width + 0.01));
          }
        }
      }
    });
  });
}
