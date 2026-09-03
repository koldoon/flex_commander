import 'dart:async';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';
import 'credentials_prompt.dart';
import 'elevation_prompt.dart';

/// Вопросы ядра — на экран.
///
/// Ядро спрашивает секрет или предлагает повышение событием; здесь это
/// превращается в открытое окно, а ответ уходит обратно просьбой. Своего
/// состояния у клиента нет: он только сводит две стороны
/// (`docs/spec/client-server.md`, §7.3).
class SecretsClient {
  SecretsClient({required Link link, required this.credentials, required this.elevation}) {
    _events = link.events.listen(_apply);
  }

  final CredentialsController credentials;
  final ElevationPrompt elevation;

  late final StreamSubscription<CoreEvent> _events;

  void _apply(CoreEvent event) {
    switch (event) {
      case CredentialAsked(:final askId, :final request):
        credentials.show(askId, request);
      case ElevationAsked(:final askId, :final request):
        elevation.show(askId, request);
      case CoreEvent():
        break;
    }
  }

  Future<void> dispose() => _events.cancel();
}
