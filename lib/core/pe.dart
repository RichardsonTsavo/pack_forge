// Leitura e edição mínima de executáveis PE (Windows).
//
// Usado pelo empacotador (verificar executáveis x64 e aplicar o ícone) e pela
// ferramenta que gera o launcher (subsistema GUI e manifest).

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int imageFileMachineAmd64 = 0x8664;
const int _imageSubsystemWindowsGui = 2;

const int _rtIcon = 3;
const int _rtGroupIcon = 14;
const int _rtManifest = 24;

class PeException implements Exception {
  PeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Retorna o campo `Machine` do cabeçalho PE, ou `null` se não for um PE.
int? readPeMachine(String path) {
  final file = File(path).openSync();
  try {
    final header = file.readSync(4096);
    final offset = _peHeaderOffset(header);
    if (offset == null) return null;
    return ByteData.sublistView(header).getUint16(offset + 4, Endian.little);
  } finally {
    file.closeSync();
  }
}

/// Altera o subsistema do executável para GUI, evitando a janela de console.
void setGuiSubsystem(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  final offset = _peHeaderOffset(bytes);
  if (offset == null) throw PeException('"$path" não é um executável PE válido.');
  // Optional header começa após assinatura (4) + file header (20); o campo
  // Subsystem fica no offset 68 tanto em PE32 quanto em PE32+.
  ByteData.sublistView(bytes)
      .setUint16(offset + 24 + 68, _imageSubsystemWindowsGui, Endian.little);
  file.writeAsBytesSync(bytes, flush: true);
}

int? _peHeaderOffset(Uint8List header) {
  if (header.length < 0x40 || header[0] != 0x4D || header[1] != 0x5A) return null;
  final offset = ByteData.sublistView(header).getUint32(0x3C, Endian.little);
  if (offset + 24 + 70 > header.length) return null;
  if (header[offset] != 0x50 ||
      header[offset + 1] != 0x45 ||
      header[offset + 2] != 0 ||
      header[offset + 3] != 0) {
    return null;
  }
  return offset;
}

class _ResourceUpdate {
  _ResourceUpdate(this.type, this.id, this.data);

  final int type;
  final int id;
  final Uint8List data;
}

/// Grava recursos no executável. Deve ser feito antes de anexar o payload,
/// porque o Windows reescreve o arquivo e descartaria dados anexados.
void _updateResources(
  String exePath,
  List<_ResourceUpdate> updates, {
  bool deleteExisting = false,
}) {
  using((arena) {
    final handle = BeginUpdateResource(arena.pcwstr(exePath), deleteExisting);
    if (handle.value.address == 0) {
      throw PeException(
        'Não foi possível abrir "$exePath" para editar recursos (erro ${handle.error}).',
      );
    }
    var ok = false;
    try {
      for (final update in updates) {
        final data = arena<Uint8>(update.data.length);
        data.asTypedList(update.data.length).setAll(0, update.data);
        final result = UpdateResource(
          handle.value,
          PCWSTR(Pointer.fromAddress(update.type)),
          PCWSTR(Pointer.fromAddress(update.id)),
          0,
          data,
          update.data.length,
        );
        if (!result.value) {
          throw PeException('Falha ao gravar recurso no executável (erro ${result.error}).');
        }
      }
      ok = true;
    } finally {
      final end = EndUpdateResource(handle.value, !ok);
      if (ok && !end.value) {
        throw PeException('Falha ao salvar recursos no executável (erro ${end.error}).');
      }
    }
  });
}

/// Substitui todos os recursos do executável por um único manifest.
void replaceResourcesWithManifest(String exePath, String manifestXml) {
  _updateResources(exePath, [
    _ResourceUpdate(_rtManifest, 1, utf8.encode(manifestXml)),
  ], deleteExisting: true);
}

/// Aplica um arquivo .ico como ícone principal do executável.
void applyIcon(String exePath, Uint8List ico) {
  final data = ByteData.sublistView(ico);
  if (ico.length < 6 ||
      data.getUint16(0, Endian.little) != 0 ||
      data.getUint16(2, Endian.little) != 1) {
    throw PeException('O arquivo selecionado não é um ícone .ico válido.');
  }
  final count = data.getUint16(4, Endian.little);
  if (count == 0 || 6 + count * 16 > ico.length) {
    throw PeException('O arquivo de ícone está vazio ou corrompido.');
  }

  final updates = <_ResourceUpdate>[];
  final group = BytesBuilder();
  final groupHeader = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, count, Endian.little);
  group.add(groupHeader.buffer.asUint8List());

  for (var i = 0; i < count; i++) {
    final entry = 6 + i * 16;
    final size = data.getUint32(entry + 8, Endian.little);
    final offset = data.getUint32(entry + 12, Endian.little);
    if (size == 0 || offset + size > ico.length) {
      throw PeException('O arquivo de ícone está corrompido.');
    }
    final id = i + 1;
    updates.add(_ResourceUpdate(_rtIcon, id, Uint8List.sublistView(ico, offset, offset + size)));

    final groupEntry = ByteData(14);
    for (var b = 0; b < 4; b++) {
      groupEntry.setUint8(b, ico[entry + b]);
    }
    groupEntry
      ..setUint16(4, data.getUint16(entry + 4, Endian.little), Endian.little)
      ..setUint16(6, data.getUint16(entry + 6, Endian.little), Endian.little)
      ..setUint32(8, size, Endian.little)
      ..setUint16(12, id, Endian.little);
    group.add(groupEntry.buffer.asUint8List());
  }
  updates.add(_ResourceUpdate(_rtGroupIcon, 1, group.takeBytes()));
  _updateResources(exePath, updates);
}
