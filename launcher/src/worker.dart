// Modo worker: executado elevado (UAC), sem interface. Faz apenas as operações
// de arquivo em Program Files e devolve o resultado pelo código de saída. O
// detalhe técnico da falha fica em `last-error.txt` na pasta de estado.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pack_forge/core/package_format.dart';
import 'package:path/path.dart' as p;

import 'layout.dart';
import 'win.dart';

final p.Context _win = p.windows;

const String workerFlag = '--pkforge-worker';

enum WorkerOperation { install, update, uninstall }

/// Códigos de saída do worker, interpretados pela interface.
abstract final class WorkerCode {
  static const ok = 0;
  static const badArguments = 2;
  static const invalidPackage = 3;
  static const busy = 4;
  static const appRunning = 5;
  static const filesInUse = 6;
  static const notOwned = 7;
  static const alreadyInstalled = 8;
  static const notInstalled = 9;
  static const accessDenied = 10;
  static const ioFailure = 11;
  static const integrityFailure = 12;
  static const partialUninstall = 13;
  static const unexpected = 99;
}

class WorkerFailure implements Exception {
  WorkerFailure(this.code, this.details);

  final int code;
  final String details;
}

int runWorker(String operationName, InstallLayout Function(PackageManifest) layoutFor) {
  final operation = WorkerOperation.values.where((o) => o.name == operationName).firstOrNull;
  if (operation == null) return WorkerCode.badArguments;

  final PackageReader package;
  try {
    package = PackageReader.open(Platform.resolvedExecutable);
  } on Object {
    return WorkerCode.invalidPackage;
  }

  final layout = layoutFor(package.manifest);
  RandomAccessFile? lock;
  final errorFile = File(layout.lastErrorFile);
  try {
    Directory(layout.stateDir).createSync(recursive: true);
    if (_isLink(layout.stateDir)) {
      throw WorkerFailure(WorkerCode.unexpected, 'Pasta de estado inválida: ${layout.stateDir}');
    }
    if (errorFile.existsSync() || _isLink(errorFile.path)) errorFile.deleteSync();

    // Impede duas operações simultâneas sobre a mesma instalação. A trava é
    // liberada pelo Windows mesmo se o processo terminar abruptamente.
    lock = File(_win.join(layout.stateDir, 'operation.lock')).openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.exclusive);
    } on FileSystemException {
      throw WorkerFailure(WorkerCode.busy, 'Outra operação já está em andamento.');
    }

    _recoverLeftovers(layout);
    switch (operation) {
      case WorkerOperation.install:
        _install(package, layout);
      case WorkerOperation.update:
        _update(package, layout);
      case WorkerOperation.uninstall:
        _uninstall(layout);
    }
    return WorkerCode.ok;
  } on WorkerFailure catch (failure) {
    _writeError(errorFile, failure.details);
    return failure.code;
  } on PackageFormatException catch (e) {
    _writeError(errorFile, e.message);
    return WorkerCode.integrityFailure;
  } on FileSystemException catch (e) {
    _writeError(errorFile, _describe(e));
    return _codeFor(e);
  } on Object catch (e, stack) {
    _writeError(errorFile, '$e\n$stack');
    return WorkerCode.unexpected;
  } finally {
    lock?.closeSync();
    package.close();
  }
}

void _install(PackageReader package, InstallLayout layout) {
  if (Directory(layout.installDir).existsSync()) {
    throw WorkerFailure(
      WorkerCode.alreadyInstalled,
      'A pasta ${layout.installDir} passou a existir durante a operação.',
    );
  }
  final staging = _extractToStaging(package, layout);
  try {
    Directory(staging).renameSync(layout.installDir);
  } on FileSystemException catch (e) {
    _tryDelete(layout, staging);
    throw WorkerFailure(_codeFor(e), 'Falha ao mover os arquivos para a pasta final: ${_describe(e)}');
  }
  setHidden(layout.installDir, false);
}

void _update(PackageReader package, InstallLayout layout) {
  _ensureOwned(layout);
  _ensureNotRunning(layout);

  // A nova versão é extraída e validada antes de tocar na instalação atual.
  final staging = _extractToStaging(package, layout);

  final backup = layout.newBackupDir();
  try {
    Directory(layout.installDir).renameSync(backup);
  } on FileSystemException catch (e) {
    _tryDelete(layout, staging);
    throw WorkerFailure(
      _codeFor(e, inUse: true),
      'A instalação atual não pôde ser substituída (algum arquivo pode estar em uso): ${_describe(e)}',
    );
  }

  try {
    Directory(staging).renameSync(layout.installDir);
  } on FileSystemException catch (e) {
    // Restaura a versão anterior.
    Directory(backup).renameSync(layout.installDir);
    _tryDelete(layout, staging);
    throw WorkerFailure(_codeFor(e), 'Falha ao ativar a nova versão; a versão anterior foi mantida: ${_describe(e)}');
  }
  setHidden(layout.installDir, false);

  // A pasta antiga é removida por inteiro. Ela é marcada como "lixo" antes,
  // para que nunca seja restaurada por engano numa recuperação futura.
  var oldDir = backup;
  try {
    final trash = layout.newTrashDir();
    Directory(backup).renameSync(trash);
    oldDir = trash;
  } on FileSystemException {
    // Segue com a exclusão do próprio backup.
  }
  _tryDelete(layout, oldDir);
}

void _uninstall(InstallLayout layout) {
  _ensureOwned(layout);
  _ensureNotRunning(layout);

  final trash = layout.newTrashDir();
  try {
    Directory(layout.installDir).renameSync(trash);
  } on FileSystemException catch (e) {
    throw WorkerFailure(
      _codeFor(e, inUse: true),
      'A pasta de instalação não pôde ser removida (algum arquivo pode estar em uso): ${_describe(e)}',
    );
  }
  try {
    _deleteTree(layout, trash);
  } on FileSystemException catch (e) {
    throw WorkerFailure(
      WorkerCode.partialUninstall,
      'Alguns arquivos não puderam ser apagados de $trash. '
      'Eles serão removidos na próxima execução deste instalador. ${_describe(e)}',
    );
  }
}

void _ensureOwned(InstallLayout layout) {
  if (!Directory(layout.installDir).existsSync()) {
    throw WorkerFailure(WorkerCode.notInstalled, 'A pasta ${layout.installDir} não existe.');
  }
  final link = FileSystemEntity.typeSync(layout.installDir, followLinks: false);
  if (link == FileSystemEntityType.link || !File(layout.installedExecutable).existsSync()) {
    throw WorkerFailure(
      WorkerCode.notOwned,
      'A pasta ${layout.installDir} não contém ${layout.mainExecutable}.',
    );
  }
}

void _ensureNotRunning(InstallLayout layout) {
  final running = runningProcessesIn(layout.installDir);
  if (running.isNotEmpty) {
    throw WorkerFailure(WorkerCode.appRunning, 'Em execução: ${running.join(', ')}');
  }
}

/// Extrai o pacote numa pasta temporária exclusiva e confere cada arquivo
/// gravado contra o hash do manifesto.
String _extractToStaging(PackageReader package, InstallLayout layout) {
  final staging = layout.newStagingDir();
  Directory(staging).createSync();
  setHidden(staging, true);
  try {
    final manifest = package.manifest;
    for (final dir in manifest.directories) {
      Directory(_safeJoin(staging, dir)).createSync(recursive: true);
    }
    for (final entry in manifest.files) {
      final data = package.readEntry(entry);
      File(_safeJoin(staging, entry.path)).writeAsBytesSync(data, flush: true);
    }
    for (final entry in manifest.files) {
      final written = File(_safeJoin(staging, entry.path)).readAsBytesSync();
      if (written.length != entry.size || sha256.convert(written).toString() != entry.sha256) {
        throw WorkerFailure(
          WorkerCode.integrityFailure,
          'O arquivo extraído "${entry.path}" não confere com o pacote.',
        );
      }
    }
    if (!File(_win.join(staging, manifest.mainExecutable)).existsSync()) {
      throw WorkerFailure(WorkerCode.integrityFailure, 'O executável principal não foi extraído.');
    }
    return staging;
  } catch (_) {
    _tryDelete(layout, staging);
    rethrow;
  }
}

/// Junta um caminho relativo do pacote à pasta de destino, garantindo que o
/// resultado continua dentro dela.
String _safeJoin(String root, String relative) {
  final target = _win.normalize(_win.joinAll([root, ...relative.split('/')]));
  if (!_win.isWithin(root, target)) {
    throw PackageFormatException('Caminho fora da pasta de destino: $relative');
  }
  return target;
}

/// Restaura uma atualização interrompida ou remove pastas temporárias antigas.
void _recoverLeftovers(InstallLayout layout) {
  final leftovers = layout.leftoverTempDirs();
  if (!Directory(layout.installDir).existsSync()) {
    final backups = leftovers.where((d) => d.path.endsWith('.old')).toList();
    if (backups.length == 1) {
      backups.single.renameSync(layout.installDir);
      setHidden(layout.installDir, false);
      leftovers.remove(backups.single);
    }
  }
  for (final dir in leftovers) {
    _tryDelete(layout, dir.path);
  }
}

void _tryDelete(InstallLayout layout, String path) {
  try {
    _deleteTree(layout, path);
  } on FileSystemException {
    // Será tentado novamente na próxima execução.
  }
}

/// Remove uma pasta temporária desta aplicação. Nunca segue links/junções e
/// recusa qualquer caminho que não seja uma pasta temporária própria.
void _deleteTree(InstallLayout layout, String path) {
  if (!layout.isOwnTempDir(path)) {
    throw StateError('Exclusão recusada fora da área controlada: $path');
  }
  if (Directory(path).existsSync()) _deleteContents(Directory(path));
}

void _deleteContents(Directory dir) {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is Link) {
      entity.deleteSync();
    } else if (entity is Directory) {
      _deleteContents(entity);
    } else {
      try {
        entity.deleteSync();
      } on FileSystemException {
        setHidden(entity.path, false); // remove somente-leitura e oculto
        entity.deleteSync();
      }
    }
  }
  setHidden(dir.path, false);
  dir.deleteSync();
}

int _codeFor(FileSystemException e, {bool inUse = false}) {
  return switch (e.osError?.errorCode) {
    5 => inUse ? WorkerCode.filesInUse : WorkerCode.accessDenied,
    32 || 33 => WorkerCode.filesInUse,
    _ => WorkerCode.ioFailure,
  };
}

bool _isLink(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.link;

String _describe(FileSystemException e) =>
    '${e.message} ${e.path ?? ''} ${e.osError?.message ?? ''}'.trim();

void _writeError(File file, String details) {
  try {
    // O worker é elevado: nunca grava através de links na pasta de estado.
    if (_isLink(file.parent.path) || _isLink(file.path)) return;
    file.writeAsStringSync(details, flush: true);
  } on FileSystemException {
    // Sem detalhes; a interface ainda mostra a mensagem do código de saída.
  }
}
