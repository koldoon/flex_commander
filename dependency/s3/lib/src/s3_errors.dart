import 'package:fc_api/fc_api.dart';

/// Что ответило хранилище — причина `FsError`, в журнал (`docs/spec/s3.md`, §14).
class S3Failure {
  const S3Failure({required this.status, required this.code, this.message = '', this.requestId});

  final int status;
  final String code;
  final String message;
  final String? requestId;

  /// Ключ отвергнут: секрет не тот или ключа нет вовсе. Тогда его забывают и
  /// спрашивают снова — как неверный пароль у FTP.
  ///
  /// Разведка на MinIO (§3): неверный секрет — `403 SignatureDoesNotMatch`,
  /// неизвестный ключ — `403 InvalidAccessKeyId`.
  bool get credentialRejected => code == 'SignatureDoesNotMatch' || code == 'InvalidAccessKeyId';

  @override
  String toString() =>
      'S3 $status $code${message.isEmpty ? '' : ': $message'}${requestId == null ? '' : ' [$requestId]'}';
}

/// Ответ хранилища — в общий вид.
FsError s3Error(String path, S3Failure failure) => FsError(path, kindOf(failure), failure);

FsErrorKind kindOf(S3Failure failure) => switch (failure.code) {
  'NoSuchKey' || 'NoSuchBucket' || 'NoSuchUpload' => FsErrorKind.notFound,
  'AccessDenied' ||
  'AllAccessDisabled' ||
  'SignatureDoesNotMatch' ||
  'InvalidAccessKeyId' => FsErrorKind.permissionDenied,
  'BucketAlreadyExists' || 'BucketAlreadyOwnedByYou' => FsErrorKind.alreadyExists,
  'InvalidBucketName' || 'KeyTooLongError' || 'XMinioInvalidObjectName' => FsErrorKind.invalidName,
  'NotImplemented' => FsErrorKind.notSupported,
  _ => switch (failure.status) {
    404 => FsErrorKind.notFound,
    403 => FsErrorKind.permissionDenied,
    501 => FsErrorKind.notSupported,
    _ => FsErrorKind.io,
  },
};

/// Отвергнут ли ключ — по ошибке, пришедшей наружу.
bool credentialRejected(Object error) =>
    error is FsError && error.cause is S3Failure && (error.cause! as S3Failure).credentialRejected;
