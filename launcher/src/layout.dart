// Caminhos controlados pelo launcher para uma aplicação.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pack_forge/core/names.dart';
import 'package:path/path.dart' as p;

final p.Context _win = p.windows;

class InstallLayout {
  InstallLayout({
    required this.programFiles,
    required this.programData,
    required this.appName,
    required this.mainExecutable,
  }) : appKey = sha256
           .convert(utf8.encode(appName.toLowerCase()))
           .toString()
           .substring(0, 12) {
    // O nome vem do pacote: é revalidado aqui antes de virar caminho.
    final error = validateAppName(appName) ?? validateMainExecutableName(mainExecutable);
    if (error != null) throw ArgumentError(error);
    if (!_win.equals(_win.dirname(installDir), programFiles)) {
      throw ArgumentError('Pasta de instalação fora de Program Files: $installDir');
    }
  }

  final String programFiles;
  final String programData;
  final String appName;
  final String mainExecutable;

  /// Identificador curto e estável da aplicação, usado nos nomes temporários.
  final String appKey;

  String get installDir => _win.join(programFiles, appName);

  String get installedExecutable => _win.join(installDir, mainExecutable);

  /// Pasta de estado do worker (trava de concorrência e último erro).
  String get stateDir => _win.join(programData, 'PackForge', appKey);

  String get lastErrorFile => _win.join(stateDir, 'last-error.txt');

  /// Pastas temporárias ao lado da instalação (mesmo volume, para que a troca
  /// seja um rename). O prefixo `.pkforge.` e o identificador aleatório evitam
  /// conflito com pastas de outros programas.
  String newStagingDir() => _temp('new');

  String newBackupDir() => _temp('old');

  String newTrashDir() => _temp('del');

  String _temp(String kind) => _win.join(programFiles, '.pkforge.$appKey.${randomHex(6)}.$kind');

  RegExp get _tempPattern => RegExp('^\\.pkforge\\.$appKey\\.[0-9a-f]{12}\\.(new|old|del)\$');

  /// Indica se [path] é uma pasta temporária desta aplicação.
  bool isOwnTempDir(String path) =>
      _win.equals(_win.dirname(path), programFiles) &&
      _tempPattern.hasMatch(_win.basename(path));

  /// Pastas temporárias que sobraram de execuções interrompidas.
  List<Directory> leftoverTempDirs() {
    final root = Directory(programFiles);
    return [
      for (final entity in root.listSync(followLinks: false))
        if (entity is Directory && isOwnTempDir(entity.path)) entity,
    ];
  }
}

String randomHex(int bytes) {
  final random = Random.secure();
  return [
    for (var i = 0; i < bytes; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
