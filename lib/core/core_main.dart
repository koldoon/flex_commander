import 'dart:async';
import 'dart:isolate';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';

import '../bootstrap/app_modules.dart';
import '../bootstrap/backend_registrations.dart';
import '../bootstrap/core_container.dart';
import '../bootstrap/registrations.dart';
import '../link/link.dart';
import 'core_server.dart';
import 'settings_store.dart';

/// **Единственный вход в изолят ядра.**
///
/// Ровно одна функция, и имя у неё говорящее: «где вход» имеет один ответ. Всё,
/// что она делает, — поднимает ядро по тем же спискам модулей, что и петля, и
/// садится разбирать просьбы из порта (`docs/spec/client-server.md`, §6).
///
/// Кода отсюда наружу и снаружи сюда не ездит: изолят получает **порт**, а
/// модули собирает у себя. Это и есть проверка того, что ядро самодостаточно —
/// собрать его, не имея экрана, должно быть возможно.
///
/// [token] нужен платформенным каналам: в порождённом изоляте их нет, пока не
/// сказано `BackgroundIsolateBinaryMessenger.ensureInitialized`
/// (`docs/spec/client-server.md`, §11, урок 11).
Future<void> coreMain(CoreStartup startup) async {
  if (startup.token case final token?) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final port = ReceivePort();
  // Первым делом — свой порт: до него та сторона говорить не может.
  startup.back.send(port.sendPort);

  final services = LazyServices();
  final registrations = BackendRegistrations(services)..installAll(backendModules());
  final container = CoreContainer(registrations, services);

  final settings = await container.get<SettingsStore>().load();
  container.bind<AppSettings>(to: (c) => settings);
  registrations.settingsSource = settings;

  final core = container.get<CoreServer>();
  final stop = core.listen((event) => startup.back.send(LinkEvent(event)));

  await for (final incoming in port) {
    if (incoming is! LinkRequest) {
      continue;
    }
    unawaited(_answer(core, incoming, startup.back));
    if (incoming.request is Shutdown) {
      break;
    }
  }

  stop();
  port.close();
}

/// Исполнить просьбу и ответить — если ответа ждут.
///
/// Чужая беда переносится текстом и исходным стеком: тип через порт не поедет,
/// а текст — это всё, что скажут человеку
/// (`docs/spec/client-server.md`, §11, урок 4).
Future<void> _answer(CoreServer core, LinkRequest incoming, SendPort back) async {
  try {
    final reply = await core.handle(incoming.request);
    if (reply != null && incoming.id != 0) {
      back.send(LinkReply(incoming.id, reply));
    }
  } on Object catch (error, stack) {
    back.send(LinkCrashed(incoming.id, error.toString(), stack.toString()));
  }
}

/// То немногое, что уезжает в изолят: порт для ответов и пропуск к каналам.
///
/// Пропуск снимается **в главном изоляте** и едет вместе с портом: в
/// порождённом спросить его уже не у кого.
class CoreStartup {
  const CoreStartup(this.back, this.token);

  final SendPort back;
  final RootIsolateToken? token;
}
