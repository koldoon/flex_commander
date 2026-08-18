import 'dart:async';

import '../../async/async_operation.dart';
import '../../async/operation_request.dart';
import '../../async/transfer_progress.dart';
import '../fs_node.dart';
import '../tree_provider.dart';

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
  const TreeTransferEngine();

  @override
  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name) {
    return TaskOperation<DirectoryNode>((op) async {
      final editor = _editorOf(parent);
      if (editor == null) {
        throw FsError(parent.pathString, FsErrorKind.notSupported);
      }

      final created = await editor.createDirectory(parent, name);
      op.checkCanceled();
      return created;
    });
  }

  @override
  AsyncOperation<void> copy(List<FsNode> nodes, DirectoryNode destination) =>
      _transfer(nodes, destination, move: false);

  @override
  AsyncOperation<void> move(List<FsNode> nodes, DirectoryNode destination) => _transfer(nodes, destination, move: true);

  /// Копирование и перемещение — одна работа с одним отличием в конце:
  /// перемещение убирает исходный объект.
  ///
  /// Существующий объект не перезаписывается молча: операция спрашивает, что
  /// делать, и запоминает ответы «…все». Ошибка на одном объекте не прекращает
  /// работу — вопрос задаётся и по ней.
  AsyncOperation<void> _transfer(List<FsNode> nodes, DirectoryNode destination, {required bool move}) {
    return TaskOperation<void>((op) async {
      // Приёмник проверяется до начала работы: менять «куда» по ходу нечем,
      // и спрашивать об этом по каждому объекту незачем.
      final target = _editorOf(destination);
      if (target == null) {
        throw FsError(destination.pathString, FsErrorKind.notSupported);
      }

      final progress = TransferProgress(op, move ? 'Moving' : 'Copying');
      var overwriteAll = false;
      var skipAll = false;

      // Подсчёт идёт рядом с работой, а не перед ней: обойти большое дерево
      // стоит почти столько же, сколько его скопировать, и стоять всё это время
      // с пустым окном незачем. Пока счёт не закончен, общее число — нижняя
      // оценка, и окно показывает это отдельно.
      unawaited(_countSources(nodes, progress));

      try {
        for (var i = 0; i < nodes.length; i++) {
          op.checkCanceled();

          final node = nodes[i];
          progress.startSource(node.name);

          try {
            final source = _editorOf(node);
            if (source == null) {
              throw FsError(node.pathString, FsErrorKind.notSupported);
            }

            if (identical(node.provider, destination.provider)) {
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

            final existing = await target.lookup(destination, node.name);
            if (existing != null) {
              if (skipAll) {
                progress.sourceDoneWholly(i);
                continue;
              }
              if (!overwriteAll) {
                final answer = await op.ask(
                  OperationRequest(
                    message: FsError(existing.pathString, FsErrorKind.alreadyExists).message,
                    options: const [
                      OperationOption.overwrite,
                      OperationOption.overwriteAll,
                      OperationOption.skip,
                      OperationOption.skipAll,
                      OperationOption.cancel,
                    ],
                    // Молча затирать чужие файлы нельзя.
                    defaultOption: OperationOption.skip,
                  ),
                );

                if (answer == OperationOption.cancel) {
                  throw const OperationCanceled();
                }
                if (answer == OperationOption.skipAll) {
                  skipAll = true;
                  progress.sourceDoneWholly(i);
                  continue;
                }
                if (answer == OperationOption.skip) {
                  progress.sourceDoneWholly(i);
                  continue;
                }
                if (answer == OperationOption.overwriteAll) {
                  overwriteAll = true;
                }
              }
              // Молча: объекты приёмника в задании не считаются.
              await _purge(target, existing, op);
            }

            // [TransferStrategy.rename]: один провайдер, и он умеет.
            if (move && identical(source, target) && await source.renameEntry(node, destination, node.name)) {
              // Переименование переносит всё поддерево одним действием —
              // поштучно объекты в нём не проходили.
              progress.sourceDoneWholly(i);
              continue;
            }

            await _copyTree(source, target, node, destination, node.name, op, progress);
            if (move) {
              await _purge(source, node, op);
            }
          } on FsError catch (error) {
            progress.sourceDoneWholly(i);
            if (skipAll) {
              continue;
            }
            final answer = await _askAboutFailure(op, error.message);
            if (answer == OperationOption.cancel) {
              throw const OperationCanceled();
            }
            if (answer == OperationOption.skipAll) {
              skipAll = true;
            }
          }
        }
      } finally {
        // Считать дальше незачем: работа кончилась — успехом, ошибкой или отменой.
        progress.stop();
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
  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true}) {
    return TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Deleting');

      // Считаем рядом с работой, а не перед ней: см. TransferProgress.
      unawaited(_countSources(nodes, progress));

      var skipAll = false;

      try {
        for (var i = 0; i < nodes.length; i++) {
          op.checkCanceled();

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
            if (answer == OperationOption.cancel) {
              throw const OperationCanceled();
            }
            if (answer == OperationOption.skipAll) {
              skipAll = true;
            }
          }
        }
      } finally {
        progress.stop();
      }

      progress.finish();
    });
  }

  /// Копирует объект вместе со всем, что под ним, отмечая каждый шаг.
  ///
  /// Каталог создаётся и обходится здесь, а не отдаётся провайдеру целиком:
  /// иначе о копировании тысячи файлов было бы известно только «начали» и
  /// «кончили», а прервать его было бы негде. Ссылка копируется как ссылка —
  /// это дело примитива, движок про ссылки ничего не решает.
  Future<void> _copyTree(
    NodeEditor source,
    NodeEditor target,
    FsNode node,
    DirectoryNode destination,
    String name,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    op.checkCanceled();
    progress.advance(node.name);

    if (node is DirectoryNode) {
      final created = await target.createDirectory(destination, name);
      // Содержимое вычитывается целиком, а не по ходу копирования: читать тот
      // же каталог, добавляя в него объекты, — верный способ уйти в петлю.
      for (final child in await source.listChildren(node)) {
        await _copyTree(source, target, child, created, child.name, op, progress);
      }
      return;
    }

    // [TransferStrategy.providerCopy]: один провайдер — копирует он сам.
    if (identical(source, target) && await source.copyEntry(node, destination, name)) {
      return;
    }

    // [TransferStrategy.stream] и [TransferStrategy.bridge] стоят на байтовом
    // контракте, которого пока нет (docs/providers.md, 5.2). Пока его нет,
    // перенос между разными провайдерами честно признаётся невозможным, а не
    // делает вид, что сработал.
    throw FsError(node.pathString, FsErrorKind.notSupported);
  }

  /// Удаляет объект вместе с содержимым, отмечая каждый шаг.
  Future<void> _deleteTree(NodeEditor editor, FsNode node, TaskOperation<void> op, TransferProgress? progress) async {
    op.checkCanceled();

    if (node is DirectoryNode) {
      // Содержимое каталога сначала вычитывается целиком: удалять объекты,
      // продолжая читать тот же каталог, — верный способ что-нибудь пропустить.
      for (final child in await editor.listChildren(node)) {
        await _deleteTree(editor, child, op, progress);
      }
    }

    progress?.advance(node.name);
    await editor.deleteEntry(node);
  }

  /// Убирает объект целиком и молча: перезапись приёмника и уборка источника
  /// после копирования в задании не считаются — там свои объекты, не наши.
  Future<void> _purge(NodeEditor editor, FsNode node, TaskOperation<void> op) async {
    if (await editor.deleteTree(node)) {
      return;
    }
    await _deleteTree(editor, node, op, null);
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
      final editor = _editorOf(nodes[i]);

      if (editor != null) {
        try {
          await editor.countEntries(nodes[i], () {
            if (progress.stopped) {
              throw const _CountingStopped();
            }
            counted++;
            progress.countOne();
          });
        } on _CountingStopped {
          return;
        } on FsError {
          // Каталог мог исчезнуть или оказаться закрытым — считаем дальше.
        }
      }

      progress.sourceCounted(i, counted);
    }

    progress.countingFinished();
  }

  Future<OperationOption> _askAboutFailure(TaskOperation<void> op, String message) {
    return op.ask(
      OperationRequest(
        message: message,
        options: const [OperationOption.skip, OperationOption.skipAll, OperationOption.cancel],
        defaultOption: OperationOption.skip,
      ),
    );
  }

  /// Примитивы провайдера, которому принадлежит узел; null — провайдер только
  /// читает.
  NodeEditor? _editorOf(FsNode node) {
    // Приведение явное: NodeEditor и TreeProvider — независимые интерфейсы,
    // и Dart не выводит одно из другого сам.
    final provider = node.provider;
    return provider is NodeEditor ? provider as NodeEditor : null;
  }
}

/// Работа кончилась раньше подсчёта — обход пора прекращать.
class _CountingStopped implements Exception {
  const _CountingStopped();
}
