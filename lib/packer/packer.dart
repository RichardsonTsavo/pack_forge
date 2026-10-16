// Gera o executável único: launcher + payload + manifest + trailer.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/names.dart';
import '../core/package_format.dart';
import '../core/pe.dart';
import 'build_inspector.dart';

class PackRequest {
  PackRequest({
    required this.buildDir,
    required this.mainExecutable,
    required this.appName,
    required this.outputPath,
    required this.iconPath,
    required this.launcherBytes,
  });

  final String buildDir;
  final String mainExecutable;
  final String appName;
  final String outputPath;
  final String? iconPath;
  final Uint8List launcherBytes;
}

class PackResult {
  PackResult({
    required this.outputPath,
    required this.fileCount,
    required this.originalBytes,
    required this.packageBytes,
    required this.buildId,
  });

  final String outputPath;
  final int fileCount;
  final int originalBytes;
  final int packageBytes;
  final String buildId;
}

class PackException implements Exception {
  PackException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef PackProgress = void Function(String stage, double? fraction);

/// Executa o empacotamento numa isolate separada, reportando o progresso.
Future<PackResult> createPackage(PackRequest request, PackProgress onProgress) async {
  final port = ReceivePort();
  port.listen((message) {
    final (stage, fraction) = message as (String, double?);
    onProgress(stage, fraction);
  });
  try {
    return await _runIsolated(request, port.sendPort);
  } finally {
    port.close();
  }
}

// Função separada para que a closure enviada à isolate capture apenas dados
// enviáveis (e não o callback da interface).
Future<PackResult> _runIsolated(PackRequest request, SendPort send) =>
    Isolate.run(() => _pack(request, (stage, fraction) => send.send((stage, fraction))));

/// Erro de validação das entradas, ou `null` se tudo estiver correto.
String? validateRequest({
  required String buildDir,
  required String? mainExecutable,
  required String appName,
  required String outputDir,
  required String outputFileName,
  required String? iconPath,
}) {
  if (buildDir.isEmpty) return 'Selecione a pasta da build.';
  if (mainExecutable == null) return 'Selecione o executável principal.';
  final appError = validateAppName(appName);
  if (appError != null) return appError;
  final fileError = validateOutputFileName(outputFileName);
  if (fileError != null) return fileError;
  if (outputDir.isEmpty) return 'Selecione a pasta onde o executável final será salvo.';
  if (!Directory(outputDir).existsSync()) return 'A pasta de saída não existe.';
  if (p.equals(outputDir, buildDir) || p.isWithin(buildDir, outputDir)) {
    return 'A pasta de saída não pode ficar dentro da pasta da build.';
  }
  if (iconPath != null) {
    if (!iconPath.toLowerCase().endsWith('.ico')) return 'O ícone deve ser um arquivo .ico.';
    if (!File(iconPath).existsSync()) return 'O arquivo de ícone não existe.';
  }
  return null;
}

PackResult _pack(PackRequest request, PackProgress progress) {
  progress('Validando a build...', null);
  final inspection = inspectBuild(request.buildDir);
  if (!inspection.isValid) throw PackException(inspection.errors.join('\n'));
  if (!inspection.executables.contains(request.mainExecutable)) {
    throw PackException('O executável principal "${request.mainExecutable}" não está na build.');
  }
  final validation = validateRequest(
    buildDir: request.buildDir,
    mainExecutable: request.mainExecutable,
    appName: request.appName,
    outputDir: p.dirname(request.outputPath),
    outputFileName: p.basename(request.outputPath),
    iconPath: request.iconPath,
  );
  if (validation != null) throw PackException(validation);

  final BuildEntries entries;
  try {
    entries = collectBuildEntries(request.buildDir);
  } on BuildContentException catch (e) {
    throw PackException(e.message);
  }

  final temp = '${request.outputPath}.${Random.secure().nextInt(1 << 32).toRadixString(16)}.partial';
  try {
    progress('Preparando o launcher...', null);
    File(temp).writeAsBytesSync(request.launcherBytes, flush: true);
    if (readPeMachine(temp) != imageFileMachineAmd64) {
      throw PackException('O launcher embutido no Pack Forge é inválido. Recompile-o.');
    }
    if (request.iconPath != null) {
      try {
        applyIcon(temp, File(request.iconPath!).readAsBytesSync());
      } on PeException catch (e) {
        throw PackException('Não foi possível aplicar o ícone: ${e.message}');
      }
    }

    final result = _appendPayload(temp, request, entries, progress);
    _verify(temp, request, progress);

    progress('Salvando o arquivo final...', null);
    final output = File(request.outputPath);
    if (output.existsSync()) output.deleteSync();
    File(temp).renameSync(request.outputPath);
    return result;
  } on FileSystemException catch (e) {
    throw PackException('Erro de arquivo: ${e.message} ${e.path ?? ''} ${e.osError?.message ?? ''}');
  } finally {
    final leftover = File(temp);
    if (leftover.existsSync()) leftover.deleteSync();
  }
}

PackResult _appendPayload(
  String temp,
  PackRequest request,
  BuildEntries entries,
  PackProgress progress,
) {
  final file = File(temp).openSync(mode: FileMode.writeOnlyAppend);
  try {
    final payloadOffset = file.lengthSync();
    var payloadLength = 0;
    var originalBytes = 0;
    final packaged = <PackageEntry>[];
    for (var i = 0; i < entries.files.length; i++) {
      final path = entries.files[i];
      progress('Compactando $path', i / entries.files.length);
      final data = File(p.joinAll([request.buildDir, ...path.split('/')])).readAsBytesSync();
      final compressed = payloadCodec.encode(data);
      file.writeFromSync(compressed);
      packaged.add(
        PackageEntry(
          path: path,
          offset: payloadLength,
          compressedSize: compressed.length,
          size: data.length,
          sha256: sha256.convert(data).toString(),
        ),
      );
      payloadLength += compressed.length;
      originalBytes += data.length;
    }

    final buildId = sha256
        .convert(utf8.encode(packaged.map((e) => '${e.path}:${e.sha256}').join('\n')))
        .toString()
        .substring(0, 16);
    final manifest = PackageManifest(
      appName: request.appName,
      mainExecutable: request.mainExecutable,
      buildId: buildId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      directories: entries.directories,
      files: packaged,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    file.writeFromSync(manifestBytes);
    file.writeFromSync(
      PackageTrailer(
        payloadOffset: payloadOffset,
        payloadLength: payloadLength,
        manifestOffset: payloadOffset + payloadLength,
        manifestLength: manifestBytes.length,
        manifestSha256: sha256.convert(manifestBytes).bytes,
      ).encode(),
    );
    file.flushSync();
    return PackResult(
      outputPath: request.outputPath,
      fileCount: packaged.length,
      originalBytes: originalBytes,
      packageBytes: file.lengthSync(),
      buildId: buildId,
    );
  } finally {
    file.closeSync();
  }
}

/// Reabre o arquivo gerado como o launcher faria e confere cada entrada.
void _verify(String temp, PackRequest request, PackProgress progress) {
  final PackageReader reader;
  try {
    reader = PackageReader.open(temp);
  } on PackageFormatException catch (e) {
    throw PackException('O arquivo gerado não passou na validação: ${e.message}');
  }
  try {
    final manifest = reader.manifest;
    if (manifest.appName != request.appName ||
        manifest.mainExecutable != request.mainExecutable) {
      throw PackException('O arquivo gerado não passou na validação: metadados divergentes.');
    }
    for (var i = 0; i < manifest.files.length; i++) {
      progress('Validando o arquivo gerado...', i / manifest.files.length);
      reader.readEntry(manifest.files[i]);
    }
  } on PackageFormatException catch (e) {
    throw PackException('O arquivo gerado não passou na validação: ${e.message}');
  } finally {
    reader.close();
  }
}
