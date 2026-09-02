import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Всплывающие сообщения поверх окна.
///
/// Лежит в общем `Stack` приложения и **места не занимает**: сообщение приходит
/// и уходит само, и сдвигать из-за него панели нельзя — строка, ради которой
/// прыгает весь экран, раздражает сильнее, чем помогает.
///
/// Показывается одно, последнее: так решает [Toasts], здесь только рисование.
class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key, required this.toasts});

  final Toasts toasts;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return Positioned.fill(
      child: IgnorePointer(
        // Сообщение ничего не спрашивает и ничем не управляет: клики сквозь
        // него должны доходить до панели, над которой оно висит.
        child: Padding(
          padding: EdgeInsets.only(bottom: metrics.toastBottomOffset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ListenableBuilder(
              listenable: toasts,
              builder: (context, _) {
                final toast = toasts.current;

                return AnimatedSwitcher(
                  duration: _fade,
                  child:
                      toast == null
                          // Пустая распорка, а не `SizedBox.shrink()`: так
                          // уходящее сообщение доигрывает исчезновение.
                          ? const SizedBox.shrink()
                          // Ключ по номеру показа, а не по тексту: два
                          // одинаковых сообщения подряд — это два показа, и
                          // второе должно моргнуть, а не остаться незамеченным.
                          : _ToastView(key: ValueKey(toast.id), message: toast.message),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static const Duration _fade = Duration(milliseconds: 150);
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.toastHorizontalPadding, vertical: metrics.toastPadding),
      decoration: BoxDecoration(
        // Оформление окна команды: тост — такая же всплывшая поверхность, и
        // заводить ему собственную палитру незачем.
        color: colors.dialogBackground,
        borderRadius: BorderRadius.circular(metrics.dialogRadius),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            offset: Offset(0, metrics.buttonShadowOffset),
            blurRadius: metrics.buttonShadowBlur,
          ),
        ],
      ),
      child: Text(message, style: theme.uiStyle.copyWith(color: colors.dialogText)),
    );
  }
}
