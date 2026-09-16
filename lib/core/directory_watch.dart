import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Слежение за показанным каталогом: изменили не мы — догоняем
/// (`docs/spec/directory-watch.md`).
///
/// Отдельным классом, а не полем внутри сессии панели: у этого своя жизнь со
/// своими правилами — подписка, накопление событий, смерть потока, — и
/// проверяется она сама по себе. Сессия только говорит, за каким каталогом
/// следить.
class DirectoryWatch {
  DirectoryWatch({
    required Future<void> Function() refresh,
    required bool Function() enabled,
    Duration Function()? delay,
  }) : _enabled = enabled,
       _settle = Settle(refresh, quiet: delay);

  final bool Function() _enabled;
  final Settle _settle;

  StreamSubscription<void>? _watching;

  /// За чем следим сейчас: источник и путь. Узел не годится — после
  /// перечитывания он другой, а каталог тот же.
  TreeProvider? _source;
  String _path = '';

  /// Конец потока уже разобран: `onError` и `onDone` приходят парой, а
  /// перечитывание нужно одно.
  bool _closed = false;

  /// Следим ли мы за чем-нибудь прямо сейчас.
  bool get watching => _watching != null;

  /// Следить за этим каталогом; null — ни за чем.
  ///
  /// **Тот же каталог второй раз не подписываем** — это главный предохранитель
  /// этапа. Система присылает события, случившиеся **до** подписки (проверено
  /// живьём), поэтому пере-подписка на каждое перечитывание закрутила бы вечный
  /// круг: событие, чтение, новая подписка, старое событие, чтение.
  void follow(DirectoryNode? dir) {
    if (!_enabled() || dir == null) {
      stop();
      return;
    }

    final source = dir.provider;
    final path = dir.pathString;
    if (_watching != null && identical(_source, source) && _path == path) {
      return;
    }

    stop();
    if (source is! WatchableSource) {
      return;
    }

    _source = source;
    _path = path;
    _closed = false;
    _watching = (source as WatchableSource)
        .watchDirectory(dir)
        .listen(
          (_) => _onEvent(),
          // Ошибка потока значит то же, что и его конец: следить больше нечем, а
          // рассказывать об этом человеку нечего — сделать он с этим ничего не
          // может (`docs/spec/directory-watch.md`, §3).
          onError: (Object _) => _onClosed(dir),
          onDone: () => _onClosed(dir),
          cancelOnError: true,
        );
  }

  /// Снять слежение, ничего не перечитывая: уходим из каталога.
  void stop() {
    unawaited(_watching?.cancel());
    _watching = null;
    _source = null;
    _path = '';
    _settle.cancel();
  }

  void dispose() => stop();

  /// Повторить попытку: сейчас не вышло, но событие терять нельзя.
  ///
  /// Так отвечает занятая панель: перечитывать её сию минуту нельзя — чтение
  /// отменило бы чужую работу, — но и забывать о случившемся незачем. Новое
  /// окно накопления доживёт до того мига, когда панель освободится.
  void retry() => _settle();

  void _onEvent() {
    // Настройку спрашиваем и здесь: выключенная снимает слежение на первом же
    // событии, даже если о правке никто не сказал.
    if (!_enabled()) {
      stop();
      return;
    }
    _settle();
  }

  /// Поток кончился: каталог удалили, переименовали, том отмонтировали.
  ///
  /// **Само закрытие ничего не перечитывает** — и это не упущение. Пустой поток
  /// («следить здесь нечем») закрывается сразу, и чтение по закрытию означало
  /// бы лишний оборот на каждом томе, который слежения не умеет.
  ///
  /// А исчезновение каталога перечитается и без того: система присылает о нём
  /// **событие**, и только потом закрывает поток — проверено живьём
  /// (`docs/spec/directory-watch.md`, §2). Событие уже завело накопление.
  ///
  /// Подписаться заново отсюда мы тоже не пробуем. Каталог мог уцелеть —
  /// атомарная подмена (`git checkout`, переезд `rsync`) выглядит для системы
  /// именно так, — но узнать это может только чтение. Выйдет оно — панель сама
  /// позовёт [follow], и слежение поднимется на новый каталог; не выйдет —
  /// звать будет некому, и круга «подписались на пустоту, поток закрылся,
  /// перечитали» не случится.
  void _onClosed(DirectoryNode dir) {
    if (_closed) {
      return;
    }
    _closed = true;
    _watching = null;
    _source = null;
    _path = '';
  }
}
