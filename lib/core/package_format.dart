// Formato do pacote anexado ao final do launcher.
//
//   [launcher.exe][payload][manifest JSON (UTF-8)][trailer de 80 bytes]
//
// payload  : blocos comprimidos (deflate raw), um por arquivo, em sequência.
// manifest : nome da aplicação, executável principal e a lista de arquivos com
//            offset relativo ao início do payload, tamanhos e SHA-256.
// trailer  : magic, versão, limites do payload e do manifest e o SHA-256 do
//            manifest. Fica sempre nos últimos 80 bytes do arquivo.
//
// Dart puro: compartilhado entre o empacotador e o launcher.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'names.dart';

const String packageMagic = 'PKFORGE1';
const int packageFormatVersion = 1;
const int trailerSize = 80;

const int maxManifestBytes = 64 * 1024 * 1024;
const int maxEntryCount = 200000;
const int maxEntrySize = 4 * 1024 * 1024 * 1024;

/// Codec usado para cada arquivo do payload (deflate sem cabeçalho zlib).
final ZLibCodec payloadCodec = ZLibCodec(raw: true, level: 6);

class PackageFormatException implements Exception {
  PackageFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PackageEntry {
  PackageEntry({
    required this.path,
    required this.offset,
    required this.compressedSize,
    required this.size,
    required this.sha256,
  });

  /// Caminho relativo separado por '/'.
  final String path;

  /// Offset do bloco comprimido em relação ao início do payload.
  final int offset;
  final int compressedSize;
  final int size;

  /// SHA-256 do conteúdo original em hexadecimal minúsculo.
  final String sha256;

  Map<String, Object> toJson() => {
    'path': path,
    'offset': offset,
    'compressedSize': compressedSize,
    'size': size,
    'sha256': sha256,
  };

  static PackageEntry fromJson(Object? json) {
    if (json is! Map) throw PackageFormatException('Entrada de arquivo inválida.');
    return PackageEntry(
      path: _string(json, 'path'),
      offset: _int(json, 'offset'),
      compressedSize: _int(json, 'compressedSize'),
      size: _int(json, 'size'),
      sha256: _string(json, 'sha256'),
    );
  }
}

class PackageManifest {
  PackageManifest({
    required this.appName,
    required this.mainExecutable,
    required this.buildId,
    required this.createdAt,
    required this.directories,
    required this.files,
  });

  final String appName;

  /// Nome do executável principal, na raiz da pasta de instalação.
  final String mainExecutable;

  /// Identificador da build, derivado dos hashes dos arquivos.
  final String buildId;
  final String createdAt;

  /// Todas as pastas do pacote (inclusive vazias), separadas por '/'.
  final List<String> directories;
  final List<PackageEntry> files;

  Map<String, Object> toJson() => {
    'formatVersion': packageFormatVersion,
    'appName': appName,
    'mainExecutable': mainExecutable,
    'buildId': buildId,
    'createdAt': createdAt,
    'directories': directories,
    'files': [for (final f in files) f.toJson()],
  };

  static PackageManifest fromJson(Object? json) {
    if (json is! Map) throw PackageFormatException('Manifesto do pacote inválido.');
    if (json['formatVersion'] != packageFormatVersion) {
      throw PackageFormatException(
        'Versão do formato do pacote não suportada: ${json['formatVersion']}.',
      );
    }
    final dirs = json['directories'];
    final files = json['files'];
    if (dirs is! List || files is! List) {
      throw PackageFormatException('Manifesto do pacote incompleto.');
    }
    return PackageManifest(
      appName: _string(json, 'appName'),
      mainExecutable: _string(json, 'mainExecutable'),
      buildId: _string(json, 'buildId'),
      createdAt: _string(json, 'createdAt'),
      directories: [
        for (final d in dirs)
          if (d is String) d else throw PackageFormatException('Pasta inválida no manifesto.'),
      ],
      files: [for (final f in files) PackageEntry.fromJson(f)],
    );
  }

  /// Valida todo o conteúdo do manifesto contra os limites do payload.
  ///
  /// Nada que venha do pacote é usado antes de passar por aqui.
  void validate(int payloadLength) {
    final appError = validateAppName(appName);
    if (appError != null) throw PackageFormatException(appError);
    final exeError = validateMainExecutableName(mainExecutable);
    if (exeError != null) {
      throw PackageFormatException('Pacote inválido: $exeError.');
    }
    if (files.isEmpty) throw PackageFormatException('O pacote não contém arquivos.');
    if (files.length > maxEntryCount || directories.length > maxEntryCount) {
      throw PackageFormatException('O pacote contém entradas demais.');
    }

    final seen = <String>{};
    for (final dir in directories) {
      final error = validateRelativePath(dir);
      if (error != null) throw PackageFormatException('Pacote inválido: $error.');
      if (!seen.add(dir.toLowerCase())) {
        throw PackageFormatException('Pacote inválido: pasta duplicada "$dir".');
      }
    }

    final dirSet = {for (final d in directories) d.toLowerCase()};
    final sha = RegExp(r'^[0-9a-f]{64}$');
    var hasMain = false;
    for (final file in files) {
      final error = validateRelativePath(file.path);
      if (error != null) throw PackageFormatException('Pacote inválido: $error.');
      if (!seen.add(file.path.toLowerCase())) {
        throw PackageFormatException('Pacote inválido: entrada duplicada "${file.path}".');
      }
      if (!sha.hasMatch(file.sha256)) {
        throw PackageFormatException('Pacote inválido: hash ausente em "${file.path}".');
      }
      if (file.offset < 0 ||
          file.compressedSize < 0 ||
          file.size < 0 ||
          file.size > maxEntrySize ||
          file.offset + file.compressedSize > payloadLength) {
        throw PackageFormatException(
          'Pacote corrompido: limites inválidos em "${file.path}".',
        );
      }
      final parent = file.path.contains('/')
          ? file.path.substring(0, file.path.lastIndexOf('/'))
          : null;
      if (parent != null && !dirSet.contains(parent.toLowerCase())) {
        throw PackageFormatException('Pacote inválido: pasta ausente para "${file.path}".');
      }
      if (file.path.toLowerCase() == mainExecutable.toLowerCase()) hasMain = true;
    }
    if (!hasMain) {
      throw PackageFormatException(
        'Pacote inválido: o executável principal "$mainExecutable" não está no pacote.',
      );
    }
  }
}

class PackageTrailer {
  PackageTrailer({
    required this.payloadOffset,
    required this.payloadLength,
    required this.manifestOffset,
    required this.manifestLength,
    required this.manifestSha256,
  });

  final int payloadOffset;
  final int payloadLength;
  final int manifestOffset;
  final int manifestLength;
  final List<int> manifestSha256;

  Uint8List encode() {
    final bytes = Uint8List(trailerSize);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, 8, ascii.encode(packageMagic));
    data.setUint32(8, packageFormatVersion, Endian.little);
    data.setUint32(12, 0, Endian.little);
    data.setUint64(16, payloadOffset, Endian.little);
    data.setUint64(24, payloadLength, Endian.little);
    data.setUint64(32, manifestOffset, Endian.little);
    data.setUint64(40, manifestLength, Endian.little);
    bytes.setRange(48, 80, manifestSha256);
    return bytes;
  }

  /// Decodifica e valida o trailer contra o tamanho real do arquivo.
  static PackageTrailer decode(Uint8List bytes, int fileLength) {
    if (bytes.length != trailerSize ||
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != packageMagic) {
      throw PackageFormatException(
        'Este executável não contém um pacote do Pack Forge ou o arquivo está corrompido.',
      );
    }
    final data = ByteData.sublistView(bytes);
    final version = data.getUint32(8, Endian.little);
    if (version != packageFormatVersion) {
      throw PackageFormatException('Versão do formato do pacote não suportada: $version.');
    }
    final trailer = PackageTrailer(
      payloadOffset: data.getUint64(16, Endian.little),
      payloadLength: data.getUint64(24, Endian.little),
      manifestOffset: data.getUint64(32, Endian.little),
      manifestLength: data.getUint64(40, Endian.little),
      manifestSha256: bytes.sublist(48, 80),
    );
    // Layout obrigatório: payload, manifest e trailer contíguos no fim do arquivo.
    final valid =
        trailer.payloadOffset > 0 &&
        trailer.payloadLength >= 0 &&
        trailer.manifestLength > 0 &&
        trailer.manifestLength <= maxManifestBytes &&
        trailer.manifestOffset == trailer.payloadOffset + trailer.payloadLength &&
        trailer.manifestOffset + trailer.manifestLength + trailerSize == fileLength;
    if (!valid) {
      throw PackageFormatException('Pacote corrompido: limites do conteúdo inválidos.');
    }
    return trailer;
  }
}

/// Leitor de um pacote, aberto a partir do próprio executável ou de um arquivo
/// gerado pelo empacotador.
class PackageReader {
  PackageReader._(this._file, this.trailer, this.manifest);

  /// Abre o pacote, valida trailer, hash do manifesto e conteúdo do manifesto.
  static PackageReader open(String path) {
    final file = File(path).openSync();
    try {
      final length = file.lengthSync();
      if (length < trailerSize) {
        throw PackageFormatException('Arquivo pequeno demais para conter um pacote.');
      }
      file.setPositionSync(length - trailerSize);
      final trailer = PackageTrailer.decode(file.readSync(trailerSize), length);

      file.setPositionSync(trailer.manifestOffset);
      final manifestBytes = file.readSync(trailer.manifestLength);
      if (manifestBytes.length != trailer.manifestLength ||
          !_sameBytes(sha256.convert(manifestBytes).bytes, trailer.manifestSha256)) {
        throw PackageFormatException('Pacote corrompido: o manifesto não confere com o hash.');
      }
      final PackageManifest manifest;
      try {
        manifest = PackageManifest.fromJson(jsonDecode(utf8.decode(manifestBytes)));
      } on FormatException {
        throw PackageFormatException('Pacote corrompido: manifesto ilegível.');
      }
      manifest.validate(trailer.payloadLength);
      return PackageReader._(file, trailer, manifest);
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  final RandomAccessFile _file;
  final PackageTrailer trailer;
  final PackageManifest manifest;

  /// Lê, descomprime e confere tamanho e SHA-256 de uma entrada.
  Uint8List readEntry(PackageEntry entry) {
    _file.setPositionSync(trailer.payloadOffset + entry.offset);
    final compressed = _file.readSync(entry.compressedSize);
    if (compressed.length != entry.compressedSize) {
      throw PackageFormatException('Pacote corrompido: "${entry.path}" está incompleto.');
    }
    final List<int> data;
    try {
      data = payloadCodec.decode(compressed);
    } on Exception {
      throw PackageFormatException('Pacote corrompido: falha ao descomprimir "${entry.path}".');
    }
    if (data.length != entry.size || sha256.convert(data).toString() != entry.sha256) {
      throw PackageFormatException('Pacote corrompido: "${entry.path}" não confere com o hash.');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  void close() => _file.closeSync();
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _string(Map json, String key) {
  final value = json[key];
  if (value is! String) throw PackageFormatException('Manifesto inválido: campo "$key".');
  return value;
}

int _int(Map json, String key) {
  final value = json[key];
  if (value is! int) throw PackageFormatException('Manifesto inválido: campo "$key".');
  return value;
}
