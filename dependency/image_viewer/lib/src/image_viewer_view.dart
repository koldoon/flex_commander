import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'image_viewer_screen.dart';

/// Показ картинки: та же рама и та же плашка, что у панели и у текста.
///
/// Вид один на оба места — во весь экран и в области панели. Разница в раме
/// (внешние края) и в том, кому достаются клавиши; и то и другое спрашивается
/// у области, а не задаётся отдельным видом.
class ImageViewerView extends StatelessWidget {
  const ImageViewerView({super.key, required this.screen});

  final ImageViewerScreen screen;

  @override
  Widget build(BuildContext context) {
    // Приложение нужно только в панели: во весь экран рама и фокус известны и
    // так — оба края внешние, ввод его.
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder: (context, _) {
        final document = screen.document;

        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          // Картинка — сплошное содержимое: ей отдана вся рама, а плашка с
          // путём ложится поверх. Отступ под заголовком нужен списку файлов,
          // где под ним начинается первая строка; здесь он только съедал бы
          // место показа.
          fillsFrame: true,
          header: FcPathPlate(
            path: screen.node.displayPath,
            // Про картинку стоит знать три вещи, и все три — в плашке.
            trailing:
                '${document.width}×${document.height} · ${document.format} · '
                '${formatBytesLong(screen.node.size)}',
            active: app == null || app.view.takesKeys(screen),
          ),
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                final shown = _shownSize(constraints);

                return Listener(
                  // Колесо **возит** картинку, а не приближает: не влезла —
                  // прокрути, как в любом просмотрщике. Масштаб — с
                  // модификатором, привычкой из браузеров.
                  onPointerSignal: (signal) {
                    if (signal is! PointerScrollEvent) {
                      return;
                    }
                    if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
                      screen.zoomBy(
                        signal.scrollDelta.dy < 0 ? ImageViewerScreen.zoomStep : 1 / ImageViewerScreen.zoomStep,
                      );
                      return;
                    }
                    screen.moveBy(-signal.scrollDelta, shown: shown, viewport: viewport);
                  },
                  child: GestureDetector(
                    // Мышью — то же самое: стрелки заняты, они листают каталог.
                    onPanUpdate: (details) => screen.moveBy(details.delta, shown: shown, viewport: viewport),
                    child: _image(shown),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _image(Size shown) {
    final document = screen.document;

    // `OverflowBox`, а не `Center`: тот отдаёт картинке ограничения области, и
    // всё, что крупнее окна, ужимается в него — «точка в точку» превращалась в
    // то же «вписать», только под форму окна. Здесь она рисуется своего
    // размера, а лишнее отрезает `ClipRect` снаружи.
    return OverflowBox(
      alignment: Alignment.center,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: screen.offset,
        child: Image(
          image: document.image,
          width: shown.width,
          height: shown.height,
          // Размер посчитан снаружи по настоящим сторонам картинки, так что
          // вписывать нечего. `contain`, а не `fill`, — на случай, когда в
          // коробке всё же окажется не то: пусть покажется меньше, чем
          // растянется в чужие пропорции.
          fit: BoxFit.contain,
          // Мелкая картинка вблизи должна остаться собой, а не расплыться:
          // точки видно точками, как в любом просмотрщике.
          filterQuality: shown.width > document.width ? FilterQuality.none : FilterQuality.medium,
          // **Не** `gaplessPlayback`: он держит прежнюю картинку, пока новая не
          // распакуется, — а коробка уже нового размера, и в ней мелькает
          // чужое. Распаковку мы делаем заранее (`warmUp`), и обычно ждать
          // нечего; но кеш картинок не бесконечен, и при беглом листании
          // распакованное успевает из него вылететь. Пустое место на миг
          // честнее, чем обрезок предыдущего снимка.
          gaplessPlayback: false,
        ),
      ),
    );
  }

  /// Какого размера показывать картинку.
  Size _shownSize(BoxConstraints constraints) {
    final scale = _scaleFor(constraints);
    return Size(screen.document.width * scale, screen.document.height * scale);
  }

  /// Во сколько раз показывать.
  ///
  /// Вписанная картинка **не растягивается**: мелкая остаётся мелкой. Иначе
  /// иконка в шестнадцать точек занимала бы весь экран мыльным пятном.
  double _scaleFor(BoxConstraints constraints) {
    if (!screen.fitToWindow) {
      return screen.zoom;
    }
    final document = screen.document;
    final byWidth = constraints.maxWidth / document.width;
    final byHeight = constraints.maxHeight / document.height;
    final fit = byWidth < byHeight ? byWidth : byHeight;
    return fit < 1 ? fit : 1;
  }

  /// Внешние края рамы: во весь экран оба, в панели — её сторона.
  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }
    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }
}
