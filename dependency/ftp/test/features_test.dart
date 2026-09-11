import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Возможности сервера из `FEAT`.
///
/// Образец настоящий — `cios.dhitechnical.com` (`docs/spec/ftp.md`, §3).
void main() {
  final real = FtpFeatures([
    ' AUTH TLS',
    ' CCC',
    ' CLNT',
    ' EPRT',
    ' EPSV',
    ' HOST',
    ' LANG C.UTF-8*',
    ' MDTM',
    ' MFF modify;UNIX.group;UNIX.mode;',
    ' MFMT',
    ' MLST modify*;perm*;size*;type*;unique*;UNIX.mode*;',
    ' PBSZ',
    ' PROT',
    ' REST STREAM',
    ' SIZE',
    ' TVFS',
    ' UTF8',
  ]);

  test('умения читаются по первому слову строки', () {
    expect(real.machineListing, isTrue, reason: 'MLST объявлен, MLSD отдельно не стоит');
    expect(real.restart, isTrue);
    expect(real.setModified, isTrue);
    expect(real.modificationTime, isTrue);
    expect(real.size, isTrue);
    expect(real.extendedPassive, isTrue);
    expect(real.utf8, isTrue);
    expect(real.authTls, isTrue);
  });

  test('чего нет, того нет', () {
    expect(real.has('SSCN'), isFalse);
    expect(FtpFeatures.none().machineListing, isFalse);
    expect(FtpFeatures.none().restart, isFalse);
  });

  test('регистр и отступы не мешают', () {
    final features = FtpFeatures(['   rest stream', 'Mlst size*;']);

    expect(features.restart, isTrue);
    expect(features.machineListing, isTrue);
  });

  test('пустые строки не считаются умением', () {
    expect(FtpFeatures(['', '   ']).has(''), isFalse);
  });
}
