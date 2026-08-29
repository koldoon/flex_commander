import 'dart:async';
import 'dart:math' as math;

import '../../async/async_operation.dart';
import '../../async/operation_request.dart';
import '../../async/transfer_progress.dart';
import '../fs_node.dart';
import '../tree_provider.dart';
import '../operation_params.dart';
import 'transfer_answers.dart';

/// Как переносится один объект. Порядок — по убыванию скорости.
enum TransferStrategy {
  /// Переименование: один провайдер, поддерево уезжает одним действием.
  rename,

  /// Копирование средствами самого провайдера: `File.copy`, серверный `COPY`.
  providerCopy,

  /// Поток `openRead → openWrite`: любой источник в любой приёмник.
  stream,

  /// Мост через временный локальный файл, когда потока не даёт одна из сторон.
  bridge,
}

/// Перенос, копирование и удаление — один раз на все провайдеры.
///
/// Здесь живёт вся механика: обход дерева, конфликты имён, вопросы
/// пользователю, счётчики прогресса, отмена и выбор стратегии. Провайдер даёт
/// только примитивы ([NodeEditor]) — один объект за раз, без рекурсии и без
/// вопросов. Так второму источнику данных (архиву, sftp) не придётся
/// переписывать эти же полтораста строк заново, а перенос между разными
/// источниками вообще становится выразимым: узлы носят своего провайдера с
/// собой, и движок спрашивает примитивы у каждой стороны отдельно.
///
/// Состояния у движка нет: он ничей и создаётся где угодно.
class TreeTransferEngine implements TreeEditor {
  const TreeTransferEngine({this.clock = DateTime.now});

  /// Часы для скорости и оценки времени. Подменяются в тестах: настоящее время
  /// в них — источник случайных отказов.
  final DateTime Function() clock;

  @override
  @override
  Operation<RenameParams, FsNode> rename() {
    return TaskOperation<RenameParams, FsNode>((op, params) async {
      final node = params.node;
      final parent = node.parentDirectory;
      final editor = node.provider is NodeEditor ? node.provider as NodeEditor : null;
      if (parent == null || editor == null) {
        throw FsError(node.pathString, FsErrorKind.notSupported);
      }

      final name = trimmedFileName(params.name);
      if (name.isEmpty || name == '.' || name == '..') {
        throw FsError(name, FsErrorKind.invalidName);
      }
      if (name == node.name) {
        // Имя не менялось: работы нет, и ошибки тоже.
        return node;
      }

      // Имя занято — отказ, а не вопрос: согласие здесь означало бы потерю
      // чужого файла, о котором человек мог и не знать
      // (`spec/rename.md`, §5).
      final taken = await editor.lookup(parent, name);
      // Найденное может быть тем же самым объектом: на файловой системе, не
      // различающей регистр, `readme.md` и `README.md` — один файл. Сравниваем
      // объекты, а не строки.
      if (taken != null && taken.pathString != node.pathString) {
        throw FsError(name, FsErrorKind.alreadyExists);
      }

      op.checkCanceled();
      // Только одним действием: провайдер, который так не умеет, переименовывать
      // не даёт — иначе за переименованием пряталась бы пересборка архива.
      if (!await editor.renameEntry(node, parent, name)) {
        throw FsError(node.pathString, FsErrorKind.notSupported);
      }

      final renamed = await editor.lookup(parent, name);
      return renamed ?? node;
    });
  }

  @override
  Operation<MakeDirectoryParams, DirectoryNode> makeDirectory() {
    return TaskOperation<MakeDirectoryParams, DirectoryNode>((op, params) async {
      final parent = params.parent;
      final editor = _editorOf(parent);
      if (editor == null) {
        throw FsError(parent.pathString, FsErrorKind.notSupported);
      }

      final created = await editor.createDirectory(parent, params.name);
      op.checkCanceled();
      return created;
    });
  }

  @override
  Operation<TransferParams, void> copy() => _transfer(move: false);

  @override
  Operation<TransferParams, void> move() => _transfer(move: true);

  /// Копирование и перемещение — одна работа с одним отличием в конце:
  /// перемещение убирает исходный объект.
  ///
  /// Существующий объект не перезаписывается молча: операция спрашивает, что
  /// делать, и запоминает ответы «…все». Ошибка на одном объекте не прекращает
  /// работу — вопрос задаётся и по ней.
  Operation<TransferParams, void> _transfer({required bool move}) {
    return TaskOperation<TransferParams, void>((op, params) async {
      final nodes = params.nodes;
      final destination = params.destination;
      final followLinks = params.followLinks;
      // Приёмник проверяется до начала работы: менять «куда» по ходу нечем,
      // и спрашивать об этом по каждому объекту незачем.
      final target = _editorOf(destination);
      if (target == null) {
        throw FsError(destination.pathString, FsErrorKind.notSupported);
      }

      final progress = TransferProgress(op, clock: clock);
      // Приёмнику, которому запись по одному обходится дорого (архив
      // пересобирается целиком), сообщаем границы работы: пусть накопит.
      final batch = _batchOf(destination.provider);
      // Именно `if`, а не `await batch?.…`: ожидание пустого значения — это
      // всё равно пауза, и она сдвигала бы начало работы у всех остальных.
      if (batch != null) {
        // О цене спрашивают **до** начала: работа, переписывающая архив
        // целиком, не должна начинаться молча — а начавшись, она уже сделана.
        await _warnAbout(batch, op);
        await batch.beginWrites(op);
        // Плечи есть только у приёмника, который применяет накопленное разом:
        // у обычного копирования этапов нет, и окно о них молчит.
        progress.beginStage(move ? 'moving' : 'copying', index: 1, count: 2);
      }
      final overwrite = _OverwritePolicy();
      final links = _LinkPolicy(follow: followLinks);
      // Предел — по слабейшей стороне: локальному диску десяток потоков только
      // на пользу, серверу столько же — способ получить отказ.
      final pool = _TransferPool(math.min(destination.provider.capabilities.maxConcurrency, _sourceConcurrency(nodes)));

      // Подсчёт идёт рядом с работой, а не перед ней: обойти большое дерево
      // стоит почти столько же, сколько его скопировать, и стоять всё это время
      // с пустым окном незачем. Пока счёт не закончен, общее число — нижняя
      // оценка, и окно показывает это отдельно.
      unawaited(_countSources(nodes, progress));

      // «Нет ли там такого» спрашивается один раз про весь приёмник, а не про
      // каждый помеченный объект: по сети каждый такой вопрос — обмен с
      // сервером, и на тысяче помеченных их набегает тысяча ещё до начала
      // работы.
      //
      // Одному источнику перечисление не окупается: приёмник бывает огромным, а
      // вопрос к нему всего один. Не вышло перечислить (каталог, в который
      // писать можно, а читать нельзя) — спрашиваем по-старому, поштучно.
      Map<String, FsNode>? present;
      if (nodes.length > 1) {
        try {
          present = {for (final entry in await destination.provider.listChildren(destination)) entry.name: entry};
        } on FsError {
          present = null;
        }
      }

      try {
        for (var i = 0; i < nodes.length; i++) {
          await op.checkpoint();

          final node = nodes[i];
          progress.startSource(node.name);

          try {
            // Примитивы источника нужны, только чтобы у него что-то забрать:
            // копировать можно и из того, кто ничего не отдаёт, кроме чтения.
            final source = _editorOf(node);
            if (move && source == null) {
              throw FsError(node.pathString, FsErrorKind.notSupported);
            }

            if (source != null && identical(node.provider, destination.provider)) {
              // Пересечься источник с приёмником могут только внутри одного
              // провайдера: у разных общих путей нет.
              if (source.isSameEntity(node, destination)) {
                throw FsError(node.pathString, FsErrorKind.alreadyExists);
              }
              if (source.isInsideSource(node, destination)) {
                // Копирование каталога в самого себя не закончилось бы никогда.
                throw FsError(node.pathString, FsErrorKind.targetInsideSource);
              }
            }

            final existing = present != null ? present[node.name] : await target.lookup(destination, node.name);
            final merging = _merges(node, existing);
            if (existing != null && !merging) {
              if (!await _resolveConflict(op, overwrite, existing)) {
                progress.sourceDoneWholly(i);
                continue;
              }
              // В задании объекты приёмника не считаются — они не наши, — но
              // и молчать о них нельзя: уборка по сети идёт минутами, а окно
              // показывало бы прежние цифры.
              await _purge(target, existing, op, progress);
            }

            // [TransferStrategy.rename]: один провайдер, и он умеет. Сначала
            // спрашиваем, потом пробуем: по сети попытка вслепую — это лишний
            // обмен с сервером на каждый объект.
            if (move &&
                // Слияние переименованием не сделать: оно подменило бы весь
                // каталог целиком вместе с чужим содержимым.
                !merging &&
                identical(source, target) &&
                node.provider.capabilities.canRename &&
                await source!.renameEntry(node, destination, node.name)) {
              // Переименование переносит всё поддерево одним действием —
              // поштучно объекты в нём не проходили.
              progress.sourceDoneWholly(i);
              continue;
            }

            Future<void> transfer() async {
              await _copyTree(source, target, node, destination, node.name, op, progress, links, overwrite, pool);
              if (move) {
                // Дожидаемся всего, что ушло в пул из этого источника: убирать
                // его, пока часть содержимого ещё летит, нельзя.
                await pool.drain();
                // Пропущенное остаётся на месте: слияние делает перенос
                // выборочным, и снести источник целиком значило бы потерять то,
                // что человек решил сохранить.
                if (overwrite.kept.isEmpty) {
                  await _purge(source!, node, op, progress);
                } else {
                  await _purgeExcept(source!, node, overwrite.kept, op, progress);
                }
              }
            }

            // Каталог идёт сам, в глубину: в полёте оказываются его файлы, а
            // не он целиком. Мелкий файл уходит в пул, крупный ведут одного:
            // прятать задержку нечем, когда файл и так занимает канал, зато
            // полоса по объекту остаётся его собственной.
            if (node is DirectoryNode || move || node.size >= _soloBytes) {
              await transfer();
            } else {
              await pool.add(transfer);
            }
          } on FsError catch (error) {
            progress.sourceDoneWholly(i);
            if (overwrite.skipAll) {
              continue;
            }
            final answer = await _askAboutFailure(op, error.message);
            if (answer == TransferAnswers.cancel) {
              throw const OperationCanceled();
            }
            if (answer == TransferAnswers.skipAll) {
              overwrite.skipAll = true;
            }
          }
        }
        // Ждём всё, что ещё летит. Ждём с проверками: просьба прервать
        // приходит и тогда, когда раздавать уже нечего, а работы идут, — и
        // услышать её должно быть кому. Проверка приходится примерно на
        // законченный файл, то есть с той же частотой, что и раньше, когда
        // файлы шли по одному.
        while (!pool.isEmpty) {
          await op.checkpoint();
          await pool.settleAny();
        }

        // Про каждый неудавшийся спрашивают тем же вопросом, что и всегда, —
        // только позже: посреди раздачи ответ всё равно догонял бы работы,
        // которые уже идут.
        for (final error in await pool.drain()) {
          if (overwrite.skipAll) {
            continue;
          }
          if (error is! FsError) {
            throw error;
          }
          final answer = await _askAboutFailure(op, error.message);
          if (answer == TransferAnswers.cancel) {
            throw const OperationCanceled();
          }
          if (answer == TransferAnswers.skipAll) {
            overwrite.skipAll = true;
          }
        }
      } finally {
        // Отмена и ошибка обрываются на полуслове: дождаться идущих всё равно
        // надо, но разбирать здесь уже нечего.
        await pool.drain();
        // Считать дальше незачем: работа кончилась — успехом, ошибкой или отменой.
        progress.stop();
        // Накопленное должно оказаться на месте при любом исходе: после
        // ошибки и отмены — тоже, иначе часть работы пропала бы молча.
        if (batch != null) {
          // Второе плечо. Сколько в нём работы, не знает никто: доля не
          // показывается, зато видно, что работа идёт.
          progress.beginStage(batch.writesStageName, index: 2, count: 2, sized: false);
          await batch.endWrites(op);
        }
      }

      progress.finish();
    });
  }

  /// Удаляет объекты — по одному, с прогрессом и возможностью отмены.
  ///
  /// Ошибка на одном объекте не прекращает работу: операция спрашивает, что
  /// делать (пропустить, пропустить все, отменить), и идёт дальше. Если вопрос
  /// никто не слушает, применяется вариант по умолчанию — «пропустить».
  @override
  Operation<RemoveParams, void> remove() {
    return TaskOperation<RemoveParams, void>((op, params) async {
      final nodes = params.nodes;
      final toTrash = params.toTrash;
      final progress = TransferProgress(op, clock: clock);

      // Границы работы — только когда всё удаляется из одного источника:
      // у разных провайдеров общей работы нет.
      final provider = nodes.isEmpty ? null : nodes.first.provider;
      final batch =
          provider != null && nodes.every((node) => identical(node.provider, provider)) ? _batchOf(provider) : null;
      if (batch != null) {
        await _warnAbout(batch, op);
        await batch.beginWrites(op);
        progress.beginStage('deleting', index: 1, count: 2);
      }

      // Считаем рядом с работой, а не перед ней: см. TransferProgress.
      unawaited(_countSources(nodes, progress));

      var skipAll = false;

      try {
        for (var i = 0; i < nodes.length; i++) {
          await op.checkpoint();

          final node = nodes[i];
          progress.startSource(node.name);

          try {
            final editor = _editorOf(node);
            if (editor == null) {
              throw FsError(node.pathString, FsErrorKind.notSupported);
            }

            if (toTrash && await editor.trashEntry(node)) {
              // Корзина — это переименование: поддерево уезжает одним действием,
              // поштучно его объекты не проходят.
              progress.sourceDoneWholly(i);
            } else {
              await _deleteTree(editor, node, op, progress);
            }
          } on FsError catch (error) {
            progress.sourceDoneWholly(i);
            if (skipAll) {
              continue;
            }

            final answer = await _askAboutFailure(op, error.message);
            if (answer == TransferAnswers.cancel) {
              throw const OperationCanceled();
            }
            if (answer == TransferAnswers.skipAll) {
              skipAll = true;
            }
          }
        }
      } finally {
        progress.stop();
        if (batch != null) {
          progress.beginStage(batch.writesStageName, index: 2, count: 2, sized: false);
          await batch.endWrites(op);
        }
      }

      progress.finish();
    });
  }

  /// Копирует объект вместе со всем, что под ним, отмечая каждый шаг.
  ///
  /// Каталог создаётся и обходится здесь, а не отдаётся провайдеру целиком:
  /// иначе о копировании тысячи файлов было бы известно только «начали» и
  /// «кончили», а прервать его было бы негде.
  Future<void> _copyTree(
    NodeEditor? source,
    NodeEditor target,
    FsNode node,
    DirectoryNode destination,
    String name,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
    _LinkPolicy links,
    _OverwritePolicy overwrite,
    _TransferPool pool,
  ) async {
    await op.checkpoint();
    progress.advance();

    // Ссылка разбирается до того, как узел сочтут файлом: ссылка на каталог
    // файлом не является, и поток по ней открыть нельзя — на этом падала
    // упаковка каталога с `.framework` внутри.
    if (node is LinkNode) {
      final FsNode? followed = await _resolveLink(source, target, node, destination, name, op, progress, links);
      if (followed == null) {
        return;
      }
      // Пошли по ссылке: дальше работаем с целью, но под именем ссылки.
      try {
        await _copyTree(source, target, followed, destination, name, op, progress, links, overwrite, pool);
      } finally {
        links.leaveLink(node);
      }
      return;
    }

    if (node is DirectoryNode) {
      // Каталог, который уже есть, берётся как есть: это и есть слияние.
      // Заводить его заново незачем, а иные приёмники на такое и отвечают
      // отказом — «уже существует».
      final present = await target.lookup(destination, name);
      final created = present is DirectoryNode ? present : await target.createDirectory(destination, name);

      // Что в приёмнике уже лежит — спрашивается **одним** перечислением, а не
      // проверкой на каждый объект. По сети проверка — это обмен с сервером, и
      // на тысяче файлов их набегает тысяча: минуты ожидания на ровном месте.
      //
      // Каталог, который мы сами только что завели, не перечисляется вовсе: он
      // пуст, и спрашивать его не о чем. Это обычный случай — копирование
      // дерева на новое место, — и он не платит за слияние ничего.
      final existing =
          present is DirectoryNode
              ? {for (final entry in await created.provider.listChildren(created)) entry.name: entry}
              : const <String, FsNode>{};

      // Содержимое вычитывается целиком, а не по ходу копирования: читать тот
      // же каталог, добавляя в него объекты, — верный способ уйти в петлю.
      for (final child in await node.provider.listChildren(node)) {
        // Вопросы задаются здесь, о файлах, а не там, о каталоге целиком: в
        // этом и состоит слияние. Каталог поверх каталога уходит вглубь молча.
        final present = existing[child.name];
        if (present != null && !_merges(child, present)) {
          if (!await _resolveConflict(op, overwrite, present)) {
            // Пропущенное считается пройденным — работы по нему больше нет, —
            // и запоминается: при переносе его нельзя убирать из источника.
            progress.advance();
            overwrite.kept.add(child.pathString);
            continue;
          }
          await _purge(target, present, op, progress);
        }
        if (child is DirectoryNode || child.size >= _soloBytes) {
          if (child is! DirectoryNode) {
            // Крупный файл ведут одного — и только после того, как мелкие
            // разлетелись: иначе его полоса делилась бы с чужими байтами.
            await pool.drain();
          }
          await _copyTree(source, target, child, created, child.name, op, progress, links, overwrite, pool);
        } else {
          await pool.add(
            () => _copyTree(source, target, child, created, child.name, op, progress, links, overwrite, pool),
          );
        }
      }
      return;
    }

    // Дальше идёт файл: его собственный ход показывается отдельно от общего —
    // иначе один большой файл выглядит как остановка работы.
    //
    // Метка нужна потому, что файлов в работе бывает несколько: по ней байты
    // достаются своему объекту, а не первому попавшемуся.
    final item = progress.startItem(node.name, bytes: node.size < 0 ? null : node.size);
    try {
      await _copyFile(source, target, node, destination, name, op, progress, item);
    } finally {
      progress.finishItem(item);
    }
  }

  /// Сам перенос байтов: стратегии по порядку.
  Future<void> _copyFile(
    NodeEditor? source,
    NodeEditor target,
    FsNode node,
    DirectoryNode destination,
    String name,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
    int item,
  ) async {
    // [TransferStrategy.providerCopy]: один провайдер — копирует он сам.
    if (source != null && identical(source, target)) {
      // Сколько байт провайдер насчитал сам: остаток движок доберёт по концу,
      // а молчащий провайдер так и останется на старом поведении.
      var reported = 0;
      bool onBytes(int bytes) {
        reported += bytes;
        progress.advanceBytes(bytes, item);
        // Ждать здесь нечем: провайдер стоит внутри своей копии. Вопрос об
        // отмене задаётся поверх идущей работы, а ответ доходит следующим
        // куском.
        return op.keepRunning();
      }

      final bool copied;
      try {
        copied = await source.copyEntry(node, destination, name, onBytes: onBytes);
      } on FsError {
        // Половина файла под настоящим именем выглядит как целый файл: копия
        // провайдера обрывается так же, как и поток, и убирать за ней нужно
        // ровно так же.
        await _discardPartial(target, destination, name);
        rethrow;
      } on OperationCanceled {
        await _discardPartial(target, destination, name);
        rethrow;
      }

      if (copied) {
        // Провайдер мог промолчать: тогда объём засчитывается целиком, как
        // раньше. Размер неизвестен — разница уйдёт в минус, и её отбросят.
        progress.advanceBytes(node.size - reported, item);
        return;
      }
    }

    // [TransferStrategy.stream]: любой источник в любой приёмник.
    if (await _streamEntry(target, node, destination, name, op, progress, item)) {
      return;
    }

    // [TransferStrategy.bridge] — мост через временный локальный файл. Движку
    // он пока не нужен: поток берёт любую пару сторон, у которых есть байты, а
    // если байтов нет ни у кого — их неоткуда взять и мосту. Понадобится он
    // источнику, который отдаёт содержимое только целым файлом (архиватор
    // внешней программой); `LocalCopySession` для этого готова — ею уже
    // пользуется zip, чтобы открыться поверх чужого источника.
    throw FsError(node.pathString, FsErrorKind.notSupported);
  }

  /// Сколько потоков выдерживают источники задания: по слабейшему из них.
  ///
  /// Источников бывает несколько и они бывают из разных мест — помеченное
  /// копируют одним заданием, а лежать оно может и на диске, и в архиве.
  int _sourceConcurrency(List<FsNode> nodes) {
    var limit = 1 << 20;
    for (final node in nodes) {
      limit = math.min(limit, node.provider.capabilities.maxConcurrency);
    }
    return limit;
  }

  /// Сливаются ли эти двое: каталог поверх каталога — слияние, а не замена.
  ///
  /// Так делают mc, Total Commander и Far, и так оно и правильно: имена
  /// совпали — это ещё не повод сносить чужое содержимое. Спрашивать здесь не о
  /// чем, вопросы будут о файлах внутри.
  bool _merges(FsNode node, FsNode? existing) => existing is DirectoryNode && node is DirectoryNode;

  /// Спрашивает, что делать с тем, что в приёмнике уже есть.
  ///
  /// false — этот объект пропускаем. Ответы «…все» помнятся на всё задание:
  /// один и тот же вопрос про сотню файлов внутри каталога — это не разговор, а
  /// наказание.
  Future<bool> _resolveConflict(TaskOperation<Object?, void> op, _OverwritePolicy overwrite, FsNode existing) async {
    if (overwrite.skipAll) {
      return false;
    }
    if (overwrite.overwriteAll) {
      return true;
    }

    final answer = await op.ask(
      OperationRequest(
        message: FsError(existing.pathString, FsErrorKind.alreadyExists).message,
        options: const [
          TransferAnswers.overwrite,
          TransferAnswers.overwriteAll,
          TransferAnswers.skip,
          TransferAnswers.skipAll,
          TransferAnswers.cancel,
        ],
        // Молча затирать чужие файлы нельзя.
        enterOption: TransferAnswers.skip,
      ),
    );

    if (answer == TransferAnswers.cancel) {
      throw const OperationCanceled();
    }
    if (answer == TransferAnswers.skipAll) {
      overwrite.skipAll = true;
      return false;
    }
    if (answer == TransferAnswers.skip) {
      return false;
    }
    if (answer == TransferAnswers.overwriteAll) {
      overwrite.overwriteAll = true;
    }
    return true;
  }

  /// Что делать со ссылкой: сохранить ссылкой, пропустить или пойти по ней.
  ///
  /// Возвращает цель, если по ссылке решено пойти; null — со ссылкой уже
  /// разобрались (сохранили или пропустили), звать дальше нечего.
  Future<FsNode?> _resolveLink(
    NodeEditor? source,
    NodeEditor target,
    LinkNode node,
    DirectoryNode destination,
    String name,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
    _LinkPolicy links,
  ) async {
    if (!links.follow) {
      if (await _storeLink(source, target, node, destination, name)) {
        progress.advanceBytes(node.size < 0 ? 0 : node.size);
        return null;
      }
      // Сохранить нечем — вот теперь спрашиваем.
      await _askAboutLink(op, node, links);
      return null;
    }

    if (!links.enterLink(node)) {
      // По этой ссылке мы уже идём выше по ветке: `dir/sub/link → dir`. Пойти
      // по ней снова — уйти в бесконечность, а промолчать — незаметно
      // выбросить часть работы. Поэтому спрашиваем, как и про всё прочее.
      await _askAboutLink(op, node, links, recursive: true);
      return null;
    }

    final FsNode? followed = await node.resolve().result;
    if (followed == null) {
      // Битая ссылка: идти некуда, и это не повод рушить всю работу.
      links.leaveLink(node);
      await _askAboutLink(op, node, links);
      return null;
    }
    return followed;
  }

  /// Кладёт ссылку ссылкой. false — этого не смог никто.
  ///
  /// Сперва свой провайдер: `copyEntry` — это «сделай копию у себя», и локальная
  /// ФС давно так и делает. Потом приёмник, если он объявил, что ссылки умеет:
  /// байтов у ссылки нет, потоком её не передать, но строку с целью отдать
  /// можно, и этого достаточно.
  ///
  /// Отказ по ходу дела (права, чужой каталог) — это `FsError`, и он тоже
  /// значит «не вышло»: дальше будет вопрос, а не упавшая работа. Умение и
  /// событие — разные вещи: про первое говорит интерфейс, про второе исключение.
  Future<bool> _storeLink(
    NodeEditor? source,
    NodeEditor target,
    LinkNode node,
    DirectoryNode destination,
    String name,
  ) async {
    if (source != null && identical(source, target) && await source.copyEntry(node, destination, name)) {
      return true;
    }

    final linker = _linkerOf(target);
    if (linker == null || node.reference.isEmpty) {
      // Пустая цель — это не ссылка, а недочитанный узел: заводить по ней
      // нечего, и лучше спросить.
      return false;
    }

    try {
      await linker.createLink(destination, name, node.reference);
      return true;
    } on FsError {
      return false;
    }
  }

  /// Умеет ли приёмник заводить ссылки; null — не умеет.
  LinkEditor? _linkerOf(NodeEditor target) => target is LinkEditor ? target as LinkEditor : null;

  /// Вопрос про ссылку — тот же, что при отказах: пропустить, пропустить все,
  /// отменить.
  Future<void> _askAboutLink(
    TaskOperation<Object?, void> op,
    LinkNode node,
    _LinkPolicy links, {
    bool recursive = false,
  }) async {
    if (links.skipAll) {
      return;
    }

    final answer = await op.ask(
      OperationRequest(
        message:
            recursive
                ? 'The link «${node.name}» points into the directory being copied'
                : 'Cannot store the link «${node.name}» as a link here',
        options: const [TransferAnswers.skip, TransferAnswers.skipAll, TransferAnswers.cancel],
        // Подменять ссылку её содержимым молча нельзя: это разные вещи и по
        // размеру, и по смыслу.
        enterOption: TransferAnswers.skip,
      ),
      // Ссылок в дереве бывает много, и идут они разом. Ответ «пропустить все»
      // на первую снимает и те вопросы, что уже встали в очередь: человек
      // сказал это один раз, и десять раз переспрашивать его незачем.
      stillNeeded: () => !links.skipAll,
    );

    if (answer == TransferAnswers.cancel) {
      throw const OperationCanceled();
    }
    if (answer == TransferAnswers.skipAll) {
      links.skipAll = true;
    }
  }

  /// [TransferStrategy.stream]: `openRead → openWrite`.
  ///
  /// Единственная стратегия, которой всё равно, одного ли провайдера источник и
  /// приёмник: байты одинаковы везде. false — байтового контракта нет у одной
  /// из сторон.
  Future<bool> _streamEntry(
    NodeEditor target,
    FsNode node,
    DirectoryNode destination,
    String name,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
    int item,
  ) async {
    final reader = _readerOf(node.provider);
    final writer = _writerOf(destination.provider);
    if (reader == null || writer == null) {
      return false;
    }

    final content = await reader.openRead(node);
    // Размер известен не всегда — приёмнику, которому он нужен вперёд, лучше
    // получить null, чем `-1` из [FsNode.unknownSize].
    final sink = await writer.openWrite(destination, name, length: node.size < 0 ? null : node.size);

    var closed = false;
    try {
      // Отмена проверяется между кусками: файл может оказаться сколь угодно
      // большим, и ждать его конца, чтобы прерваться, незачем. `asyncMap`, а не
      // `map`: проверка умеет ждать (вопрос о прерывании), и на это время поток
      // должен встать, а не копиться в приёмнике.
      await sink.addStream(
        content.asyncMap((chunk) async {
          await op.checkpoint();
          // Единственное место, где видно движение внутри файла: на большом
          // файле только эти байты и говорят, что работа идёт.
          progress.advanceBytes(chunk.length, item);
          return chunk;
        }),
      );
      closed = true;
      await sink.close();
    } catch (error, stackTrace) {
      if (!closed) {
        await _closeQuietly(sink);
      }
      // Половина файла под настоящим именем выглядит как целый файл — этого
      // нельзя оставлять ни после ошибки, ни после отмены.
      await _discardPartial(target, destination, name);

      if (error is FsError || error is OperationCanceled) {
        rethrow;
      }
      // Провайдер вправе не переводить ошибки байтового ввода-вывода сам:
      // движок доводит их до общего вида, сохраняя причину.
      Error.throwWithStackTrace(FsError(node.pathString, FsErrorKind.io, error), stackTrace);
    }
    return true;
  }

  Future<void> _closeQuietly(StreamSink<List<int>> sink) async {
    try {
      await sink.close();
    } catch (_) {
      // Приёмник и так уже сломан: важна первая ошибка, а не эта.
    }
  }

  /// Убирает недописанный файл. Не вышло — значит не вышло: рассказывать нужно
  /// о том, из-за чего работа прервалась, а не об уборке за ней.
  Future<void> _discardPartial(NodeEditor target, DirectoryNode destination, String name) async {
    try {
      final partial = await target.lookup(destination, name);
      if (partial == null) {
        return;
      }
      if (!await target.deleteTree(partial)) {
        await target.deleteEntry(partial);
      }
    } on FsError {
      return;
    }
  }

  /// Удаляет объект вместе с содержимым, отмечая каждый шаг.
  Future<void> _deleteTree(
    NodeEditor editor,
    FsNode node,
    TaskOperation<Object?, void> op,
    TransferProgress? progress, {
    bool counts = true,
  }) async {
    await op.checkpoint();

    if (node is DirectoryNode) {
      // Содержимое каталога сначала вычитывается целиком: удалять объекты,
      // продолжая читать тот же каталог, — верный способ что-нибудь пропустить.
      for (final child in await node.provider.listChildren(node)) {
        await _deleteTree(editor, child, op, progress, counts: counts);
      }
    }

    if (counts) {
      progress?.advance();
      // Байты удалённого — тоже сделанная работа: на большом дереве доля
      // по объектам и доля по объёму расходятся втрое.
      progress?.advanceBytes(node.size);
    } else {
      // Уборка по дороге: рассказываем, но в счёт задания не берём.
      progress?.chore(node.name);
    }
    await editor.deleteEntry(node);
  }

  /// Убирает объект целиком: перезапись приёмника и уборка источника после
  /// копирования в задании не считаются — там свои объекты, не наши.
  ///
  /// Не считаются — но и не молчат. Провайдер, который умеет убрать поддерево
  /// одним действием, справляется мгновенно; тот, который не умеет (SFTP),
  /// обходит его поштучно, и по сети это минуты. Молчащее окно в это время
  /// неотличимо от зависшего.
  Future<void> _purge(
    NodeEditor editor,
    FsNode node,
    TaskOperation<Object?, void> op, [
    TransferProgress? progress,
  ]) async {
    progress?.chore(node.name);
    try {
      if (await editor.deleteTree(node)) {
        return;
      }
      await _deleteTree(editor, node, op, progress, counts: false);
    } finally {
      progress?.choreDone();
    }
  }

  /// Убирает источник после переноса, не трогая того, чего не переносили.
  ///
  /// Слияние делает перенос выборочным: файл, о котором ответили «пропустить»,
  /// остался в источнике не по случайности — его туда не клали заново. Снести
  /// его вместе с остальным значило бы потерять ровно то, что человек решил
  /// сохранить. Каталог, в котором такой файл лежит, тоже остаётся.
  ///
  /// Возвращает true, если объект убран.
  Future<bool> _purgeExcept(
    NodeEditor editor,
    FsNode node,
    Set<String> kept,
    TaskOperation<Object?, void> op,
    TransferProgress? progress,
  ) async {
    await op.checkpoint();
    if (kept.contains(node.pathString)) {
      return false;
    }

    if (node is DirectoryNode) {
      var emptied = true;
      for (final child in await node.provider.listChildren(node)) {
        emptied = await _purgeExcept(editor, child, kept, op, progress) && emptied;
      }
      if (!emptied) {
        return false;
      }
    }

    progress?.chore(node.name);
    await editor.deleteEntry(node);
    return true;
  }

  /// Фоновый подсчёт объектов задания.
  ///
  /// Ошибка обхода не прекращает работу: это оценка, а не сама операция, и
  /// недосчитанный каталог хуже, чем несделанное копирование.
  Future<void> _countSources(List<FsNode> nodes, TransferProgress progress) async {
    for (var i = 0; i < nodes.length; i++) {
      if (progress.stopped) {
        return;
      }

      var counted = 0;
      var countedBytes = 0;
      final provider = nodes[i].provider;

      try {
        await provider.countEntries(nodes[i], (bytes) {
          if (progress.stopped) {
            throw const _CountingStopped();
          }
          counted++;
          countedBytes += bytes;
          progress.countOne(bytes);
        });
      } on _CountingStopped {
        return;
      } on FsError {
        // Каталог мог исчезнуть или оказаться закрытым — считаем дальше.
      }

      progress.sourceCounted(i, counted, countedBytes);
    }

    progress.countingFinished();
  }

  Future<OperationRequestOption> _askAboutFailure(TaskOperation<Object?, void> op, String message) {
    return op.ask(
      OperationRequest(
        message: message,
        options: const [TransferAnswers.skip, TransferAnswers.skipAll, TransferAnswers.cancel],
        enterOption: TransferAnswers.skip,
      ),
    );
  }

  /// Байтовое чтение провайдера; null — содержимого он не отдаёт.
  FileContentProvider? _readerOf(TreeProvider provider) =>
      provider is FileContentProvider ? provider as FileContentProvider : null;

  /// Границы работы; null — провайдеру они не нужны.
  BatchedWrites? _batchOf(TreeProvider provider) => provider is BatchedWrites ? provider as BatchedWrites : null;

  /// Предупреждает о цене работы и, получив отказ, не даёт ей начаться.
  ///
  /// Спрашивает движок, а не провайдер: разговор с человеком принадлежит
  /// работе, и второго заводить незачем. Молчать провайдер вправе — тогда и
  /// вопроса нет.
  static Future<void> _warnAbout(BatchedWrites batch, OperationContext op) async {
    final warning = batch.writesWarning;
    if (warning == null) {
      return;
    }
    final answer = await op.ask(
      OperationRequest(
        message: warning,
        options: const [TransferAnswers.proceed, TransferAnswers.cancel],
        // Умолчание — «начать»: человек уже сказал, чего хочет, нажав `F5`.
        // Отказ отдельным нажатием, как и всюду.
        enterOption: TransferAnswers.proceed,
        escapeOption: TransferAnswers.cancel,
      ),
    );
    if (answer == TransferAnswers.cancel) {
      throw const OperationCanceled();
    }
  }

  /// Байтовая запись; null — принять содержимое он не может.
  FileContentReceiver? _writerOf(TreeProvider provider) =>
      provider is FileContentReceiver ? provider as FileContentReceiver : null;

  /// Примитивы провайдера, которому принадлежит узел; null — провайдер только
  /// читает.
  NodeEditor? _editorOf(FsNode node) {
    // Приведение явное: NodeEditor и TreeProvider — независимые интерфейсы,
    // и Dart не выводит одно из другого сам.
    final provider = node.provider;
    return provider is NodeEditor ? provider as NodeEditor : null;
  }
}

/// Файл крупнее этого идёт один: параллель придумана, чтобы прятать задержку,
/// а файл, который сам занимает канал, прятать нечего.
///
/// Мегабайт — с запасом над произведением полосы на задержку: при 10 МБ/с и
/// 25 мс в полёте имеет смысл держать четверть мегабайта.
const int _soloBytes = 1024 * 1024;

/// Сколько файлов идёт разом.
///
/// Мелкий файл — это три обмена с сервером (открыть, записать, закрыть), и
/// каждый из них ждёт ответа. По сети с задержкой в 25 мс тысяча файлов
/// проведёт в ожидании две минуты, ничего при этом не передавая. Пока один
/// ждёт, другие успевают отправить своё — этим пул и занят.
///
/// Предел спрашивают у обоих провайдеров: сколько выдерживает **тот, кто
/// слабее**.
///
/// Ошибки пул **копит, а не бросает**: неудача на одном объекте не прекращает
/// работу над остальными — это правило старше пула, и ломать его он не вправе.
/// Спрашивают по ним потом, когда все доиграли: ответ «отменить», данный
/// посреди раздачи, всё равно догонял бы уже начатые работы.
class _TransferPool {
  _TransferPool(int limit) : limit = limit < 1 ? 1 : limit;

  final int limit;

  final Set<Future<void>> _running = {};

  final List<Object> _errors = [];

  bool get isEmpty => _running.isEmpty;

  /// Ставит работу в пул, дождавшись свободного места.
  Future<void> add(Future<void> Function() work) async {
    while (_running.length >= limit) {
      await Future.any(_running);
    }

    final slot = Completer<void>();
    _running.add(slot.future);
    unawaited(
      work().then((_) {}, onError: (Object error) => _errors.add(error)).whenComplete(() {
        _running.remove(slot.future);
        slot.complete();
      }),
    );
  }

  /// Ждёт, пока закончится хоть одна из идущих работ.
  Future<void> settleAny() async {
    if (_running.isEmpty) {
      return;
    }
    await Future.any(_running);
  }

  /// Ждёт, пока пул опустеет, и отдаёт накопившиеся ошибки — по одной на
  /// неудавшийся объект, в порядке, в котором они случились.
  Future<List<Object>> drain() async {
    while (_running.isNotEmpty) {
      await Future.wait(_running.toList());
    }
    final errors = [..._errors];
    _errors.clear();
    return errors;
  }
}

/// Что делать с тем, что в приёмнике уже есть.
///
/// Одна на всё задание: ответы «…все» на то и «все», чтобы не спрашивать о
/// каждом файле внутри каталога заново.
class _OverwritePolicy {
  bool overwriteAll = false;
  bool skipAll = false;

  /// Пути источников, которые решено не переносить.
  ///
  /// Нужны переносу: пропущенное остаётся в источнике, и убирать его нельзя.
  final Set<String> kept = {};
}

/// Работа кончилась раньше подсчёта — обход пора прекращать.
class _CountingStopped implements Exception {
  const _CountingStopped();
}

/// Что делать со ссылками в этой работе.
///
/// Живёт на всю работу, а не на объект: «пропустить все» должно действовать до
/// конца, а пройденные цели — помнить всю ветку обхода.
class _LinkPolicy {
  _LinkPolicy({required this.follow});

  /// Идти по ссылкам или переносить их ссылками.
  final bool follow;

  /// Больше не спрашивать: пропускать все ссылки, которые сохранить нечем.
  bool skipAll = false;

  /// Дальше этого числа вложенных ссылок не идём.
  ///
  /// Предохранитель на случай, когда петлю не опознать по цели: относительные
  /// ссылки (`../..`) могут ходить по кругу, ни разу не повторившись строкой.
  static const int maxDepth = 32;

  /// Куда ведут ссылки, по которым мы сейчас идём, — вся ветка обхода.
  ///
  /// Именно ветка: одна и та же ссылка может честно встретиться в разных
  /// ветках, и это не петля. А вот встреча с ней **внутри неё самой** — петля
  /// и есть.
  ///
  /// По цели, а не по пути: цель ссылки остаётся ребёнком самой ссылки, и путь
  /// у неё идёт через ссылку — сравнивать пути бесполезно.
  final Set<String> _following = {};

  /// Входим в ссылку. false — по ней уже идём или зашли слишком глубоко.
  bool enterLink(LinkNode node) {
    if (_following.length >= maxDepth) {
      return false;
    }
    return _following.add(node.reference);
  }

  void leaveLink(LinkNode node) => _following.remove(node.reference);
}
