import '../../async/async_operation.dart';
import '../../async/operation_request.dart';
import '../fs_node.dart';
import '../tree_provider.dart';
import 'transfer_answers.dart';

/// Возврат файла хозяину: архив, живший на временной копии, встаёт на своё
/// место.
///
/// Общее для всех архиваторов: zip, 7z и всё, что откроется через копию, —
/// пересобирают они по-своему, а возвращают одинаково. Здесь нет ни `dart:io`,
/// ни знания о форматах: содержимое приходит потоком, а куда его класть, знает
/// сам узел-хозяин.
abstract final class WriteBack {
  /// Можно ли вернуть файл на место.
  ///
  /// Три условия, и все обязательны: принять содержимое — чтобы залить,
  /// править дерево — чтобы убрать недописанное, и **переименовывать** — чтобы
  /// заменить оригинал одним действием.
  ///
  /// Последнее условие отсекает больше, чем кажется: `zip` переименовывать не
  /// умеет вовсе (`canRename: false`), и архив внутри архива поэтому остаётся
  /// читающим, как и был. Это не досадная мелочь, а то же самое правило: без
  /// замены одним действием обрыв на середине оставил бы вместо архива
  /// обрубок. Сервер и диск переименовывать умеют — там запись и появляется.
  static bool possible(FsNode host) {
    final parent = host.parentDirectory;
    if (parent == null) {
      return false;
    }
    final provider = parent.provider;
    if (provider is! FileContentReceiver || provider is! NodeEditor) {
      return false;
    }
    return provider.capabilities.canRename;
  }

  /// Заливает [bytes] рядом с [host] и переименовывает поверх него.
  ///
  /// До самого переименования оригинал цел: оборвалась связь — остался прежний
  /// архив, а не обрубок. Сорвалось — спрашиваем, повторить ли: пересобранный
  /// файл уже готов, и терять его из-за одного обрыва незачем.
  /// Сколько раз подряд соглашаемся повторить без человека.
  ///
  /// Спросить его можно не всегда — работу мог запустить сценарий, — а
  /// «повторить» по умолчанию означало бы вечный круг на той неудаче, которая
  /// сама не пройдёт. Три попытки лечат моргнувшую сеть и не лечат непосильное.
  static const int _attempts = 3;

  static Future<void> send({
    required FsNode host,
    required Stream<List<int>> Function() bytes,
    required int size,
    OperationContext? op,
    String stageName = 'sending back',
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _once(host: host, bytes: bytes, size: size, op: op, stageName: stageName);
        return;
      } on OperationCanceled {
        rethrow;
      } on FsError catch (error) {
        // «Так я не умею» повтором не лечится: спрашивать про это — издеваться.
        if (error.kind == FsErrorKind.notSupported || attempt >= _attempts) {
          rethrow;
        }
        if (!await _askRetry(host, error, op)) {
          rethrow;
        }
      } catch (error) {
        if (attempt >= _attempts || !await _askRetry(host, error, op)) {
          rethrow;
        }
      }
    }
  }

  /// Спрашивает, повторять ли. Спросить некого — считаем, что да: моргнувшая
  /// сеть чинится сама, а число попыток ограничено.
  static Future<bool> _askRetry(FsNode host, Object error, OperationContext? op) async {
    if (op == null) {
      return true;
    }
    final answer = await op.ask(
      OperationRequest(
        message: 'Could not send «${host.name}» back: $error',
        options: const [TransferAnswers.retry, TransferAnswers.cancel],
        enterOption: TransferAnswers.retry,
        escapeOption: TransferAnswers.cancel,
      ),
    );
    return answer == TransferAnswers.retry;
  }

  static Future<void> _once({
    required FsNode host,
    required Stream<List<int>> Function() bytes,
    required int size,
    required OperationContext? op,
    required String stageName,
  }) async {
    final parent = host.parentDirectory;
    final provider = parent?.provider;
    if (parent == null || provider is! FileContentReceiver || provider is! NodeEditor) {
      throw FsError(host.pathString, FsErrorKind.notSupported);
    }
    final receiver = provider as FileContentReceiver;
    final editor = provider as NodeEditor;

    // Имя временное и заметное: если уборка почему-то не случится, по нему
    // видно, кто наследил.
    final temporary = '.${host.name}.fc-part';
    op?.report(stageName: stageName, itemName: host.name, bytesTotal: size, itemBytesTotal: size);

    final sink = await receiver.openWrite(parent, temporary, length: size);
    var sent = 0;
    try {
      await for (final chunk in bytes()) {
        op?.checkCanceled();
        sink.add(chunk);
        sent += chunk.length;
        op?.report(itemName: host.name, bytesTransferred: sent, bytesTotal: size, itemBytesTransferred: sent);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      await _removeLeftover(editor, parent, temporary);
      rethrow;
    }

    // Оригинал заменяется одним действием — до этого мгновения он цел.
    final uploaded = await editor.lookup(parent, temporary);
    if (uploaded == null || !await editor.renameEntry(uploaded, parent, host.name)) {
      await _removeLeftover(editor, parent, temporary);
      throw FsError(host.pathString, FsErrorKind.notSupported);
    }
  }

  /// Убирает недописанное: обрубок рядом с архивом — худший род мусора.
  static Future<void> _removeLeftover(NodeEditor editor, DirectoryNode parent, String name) async {
    final leftover = await editor.lookup(parent, name);
    if (leftover != null) {
      await editor.deleteEntry(leftover);
    }
  }
}
