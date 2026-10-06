import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_viewer_screen.dart';
import 'media_controls.dart';
import 'media_spectrum.dart';

/// Показ звукового файла: обложка и теги по центру, плашка управления внизу
/// (`docs/spec/audio-viewer.md`, §1). Рама и плашка пути — как у всех показов.
class AudioViewerView extends StatefulWidget {
  const AudioViewerView({super.key, required this.screen});

  final AudioViewerScreen screen;

  @override
  State<AudioViewerView> createState() => _AudioViewerViewState();
}

class _AudioViewerViewState extends State<AudioViewerView> {
  /// Обложка не крупнее этого, в точках.
  static const double _artMax = 360;

  AudioViewerScreen get screen => widget.screen;

  final FocusNode _focus = FocusNode(debugLabel: 'AudioViewerView');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Фокус ходит за областью — как у показа видео.
  void _followFocus(bool focused) {
    if (focused == _focused) {
      return;
    }
    _focused = focused;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_focused) {
        _focus.requestFocus();
      } else {
        _focus.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder: (context, _) {
        final focused = app == null || app.view.takesKeys(screen);
        _followFocus(focused);
        final theme = FcTheme.of(context);
        final metrics = theme.metrics;
        final player = screen.player;
        final tags = player.tags;
        final byLine = [tags.artist, tags.album].where((part) => part.isNotEmpty).join(' — ');

        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          header: FcPathPlate(path: screen.entry.path, trailing: formatClock(player.duration), active: focused),
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focus.requestFocus,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final art = (constraints.maxHeight * 0.4).clamp(64.0, _artMax);
                  return Column(
                    children: [
                      const Spacer(),
                      SizedBox.square(dimension: art, child: _artwork(theme, tags)),
                      SizedBox(height: metrics.dialogSectionGap * 2),
                      _line(
                        tags.title.isNotEmpty ? tags.title : screen.entry.name,
                        theme.headingStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
                      ),
                      if (byLine.isNotEmpty) ...[
                        SizedBox(height: metrics.dialogLineGap),
                        _line(byLine, theme.dialogTextStyle),
                      ],
                      if (tags.year.isNotEmpty) ...[
                        SizedBox(height: metrics.dialogLineGap),
                        _line(tags.year, theme.dialogTextStyle.copyWith(color: theme.colors.secondaryText)),
                      ],
                      const Spacer(),
                      // Спектр — над плашкой, по её ширине (§7).
                      SizedBox(
                        width: (constraints.maxWidth - 32).clamp(0.0, 560.0),
                        height: (constraints.maxHeight * 0.15).clamp(40.0, 120.0),
                        child: MediaSpectrum(player: player, playing: screen.playing),
                      ),
                      SizedBox(height: metrics.dialogGap),
                      // Плашка не прячется: смотреть, кроме неё, не на что (§1).
                      MediaControls(
                        playing: screen.playing,
                        position: screen.position,
                        duration: player.duration,
                        muted: screen.settings.muted,
                        volume: screen.settings.volume,
                        onPlayPause: screen.togglePlay,
                        onSeek: screen.seekTo,
                        onToggleMute: screen.toggleMute,
                        onVolume: screen.setVolume,
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Обложка из файла; нет её — крупная нота.
  Widget _artwork(FcTheme theme, SystemAudioTags tags) {
    final bytes = tags.artwork;
    if (bytes != null) {
      // Декодировать в размере показа, а не целиком: обложка 3000×3000 — это
      // ~36 МБ (§7.4). Размер — наибольший, а не нынешний: иначе каждый шаг
      // изменения окна менял бы ключ кэша и декодировал обложку заново.
      final pixels = (_artMax * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: ResizeImage(MemoryImage(bytes), width: pixels, height: pixels, policy: ResizeImagePolicy.fit),
          fit: BoxFit.contain,
          // Испорченная обложка — нота, а не красный экран.
          errorBuilder: (context, error, stack) => _note(theme),
        ),
      );
    }
    return _note(theme);
  }

  Widget _note(FcTheme theme) => LayoutBuilder(
    builder:
        (context, constraints) => Icon(
          theme.icons.music,
          size: constraints.maxHeight * 0.5,
          color: theme.colors.secondaryText.withValues(alpha: 0.6),
        ),
  );

  Widget _line(String text, TextStyle style) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
  );

  /// Клавиши внутри показа (§4). Команды с `Cmd` идут мимо — их разбирает
  /// реестр.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final handled = switch (event.logicalKey) {
      LogicalKeyboardKey.space => () => screen.togglePlay(),
      LogicalKeyboardKey.arrowLeft => () => screen.seekBy(-AudioViewerScreen.seekStep),
      LogicalKeyboardKey.arrowRight => () => screen.seekBy(AudioViewerScreen.seekStep),
      LogicalKeyboardKey.arrowUp => () => screen.changeVolume(AudioViewerScreen.volumeStep),
      LogicalKeyboardKey.arrowDown => () => screen.changeVolume(-AudioViewerScreen.volumeStep),
      LogicalKeyboardKey.keyM => () => screen.toggleMute(),
      LogicalKeyboardKey.home => () => screen.seekTo(Duration.zero),
      LogicalKeyboardKey.end => () => screen.seekTo(screen.player.duration),
      LogicalKeyboardKey.pageDown => () => screen.next(),
      LogicalKeyboardKey.pageUp => () => screen.previous(),
      _ => null,
    };
    if (handled == null) {
      return KeyEventResult.ignored;
    }
    handled();
    return KeyEventResult.handled;
  }

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
