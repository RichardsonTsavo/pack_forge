// Inspeção da pasta de saída de `flutter build windows --release`.

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../core/names.dart';
import '../core/pe.dart';

class BuildInspection {
  BuildInspection({
    required this.buildDir,
    required this.executables,
    required this.errors,
    required this.fileCount,
    required this.totalBytes,
    required this.suggestedIcon,
  });

  final String buildDir;

  /// Executáveis x64 na raiz da build (somente o nome do arquivo).
  final List<String> executables;

  /// Problemas que impedem o empacotamento.
  final List<String> errors;
  final int fileCount;
  final int totalBytes;

  /// `windows/runner/resources/app_icon.ico` do projeto, se a build estiver
  /// dentro da pasta de um projeto Flutter.
  final String? suggestedIcon;

  bool get isValid => errors.isEmpty;
}

/// Arquivos que toda build release do Flutter Windows precisa ter.
const _requiredFiles = ['flutter_windows.dll', 'data/icudtl.dat', 'data/app.so'];

/// Executa [inspectBuild] fora da isolate da interface.
Future<BuildInspection> inspectBuildInBackground(String buildDir) =>
    Isolate.run(() => inspectBuild(buildDir));

BuildInspection inspectBuild(String buildDir) {
  final errors = <String>[];
  final dir = Directory(buildDir);
  if (!dir.existsSync()) {
    return BuildInspection(
      buildDir: buildDir,
      executables: const [],
      errors: ['A pasta selecionada não existe.'],
      fileCount: 0,
      totalBytes: 0,
      suggestedIcon: null,
    );
  }

  final executables = <String>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
      try {
        if (readPeMachine(entity.path) == imageFileMachineAmd64) {
          executables.add(p.basename(entity.path));
        }
      } on FileSystemException {
        // Arquivo ilegível: tratado na coleta de arquivos.
      }
    }
  }
  executables.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (executables.isEmpty) {
    errors.add('Nenhum executável Windows x64 (.exe) foi encontrado na raiz da pasta.');
  }

  for (final required in _requiredFiles) {
    if (!File(p.joinAll([buildDir, ...required.split('/')])).existsSync()) {
      errors.add(
        required == 'data/app.so'
            ? 'O arquivo data/app.so não existe. A pasta parece ser de uma build debug; '
                  'use "flutter build windows --release".'
            : 'O arquivo obrigatório "$required" não foi encontrado.',
      );
    }
  }
  if (!Directory(p.join(buildDir, 'data', 'flutter_assets')).existsSync()) {
    errors.add('A pasta obrigatória "data/flutter_assets" não foi encontrada.');
  }

  var fileCount = 0;
  var totalBytes = 0;
  try {
    for (final item in collectBuildEntries(buildDir).files) {
      fileCount++;
      totalBytes += File(p.joinAll([buildDir, ...item.split('/')])).lengthSync();
    }
  } on BuildContentException catch (e) {
    errors.add(e.message);
  }

  if (executables.isEmpty && !File(p.join(buildDir, 'flutter_windows.dll')).existsSync()) {
    errors.insert(0, 'A pasta selecionada não parece ser uma build Flutter Windows (release).');
  }

  return BuildInspection(
    buildDir: buildDir,
    executables: executables,
    errors: errors,
    fileCount: fileCount,
    totalBytes: totalBytes,
    suggestedIcon: _findProjectIcon(buildDir),
  );
}

class BuildContentException implements Exception {
  BuildContentException(this.message);

  final String message;
}

class BuildEntries {
  BuildEntries(this.directories, this.files);

  /// Caminhos relativos separados por '/', em ordem.
  final List<String> directories;
  final List<String> files;
}

/// Lista recursivamente pastas e arquivos da build, validando cada caminho.
BuildEntries collectBuildEntries(String buildDir) {
  final directories = <String>[];
  final files = <String>[];
  void walk(Directory dir) {
    final children = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final entity in children) {
      final relative = p.relative(entity.path, from: buildDir).replaceAll('\\', '/');
      if (entity is Link) {
        throw BuildContentException(
          'A build contém um atalho simbólico/junção ("$relative"), que não é suportado.',
        );
      }
      final error = validateRelativePath(relative);
      if (error != null) throw BuildContentException('Arquivo não suportado na build: $error.');
      if (entity is Directory) {
        directories.add(relative);
        walk(entity);
      } else {
        files.add(relative);
      }
    }
  }

  walk(Directory(buildDir));
  if (files.isEmpty) throw BuildContentException('A pasta selecionada está vazia.');
  return BuildEntries(directories, files);
}

String? _findProjectIcon(String buildDir) {
  var current = Directory(buildDir).absolute;
  for (var i = 0; i < 8; i++) {
    final icon = File(p.join(current.path, 'windows', 'runner', 'resources', 'app_icon.ico'));
    if (icon.existsSync()) return icon.path;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}
