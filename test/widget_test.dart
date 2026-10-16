import 'package:flutter_test/flutter_test.dart';
import 'package:pack_forge/core/names.dart';
import 'package:pack_forge/core/package_format.dart';

PackageManifest _manifest({List<String>? dirs, List<PackageEntry>? files}) => PackageManifest(
  appName: 'Meu App',
  mainExecutable: 'meu_app.exe',
  buildId: 'abc',
  createdAt: '2026-01-01T00:00:00Z',
  directories: dirs ?? ['data'],
  files:
      files ??
      [
        PackageEntry(path: 'meu_app.exe', offset: 0, compressedSize: 10, size: 20, sha256: 'a' * 64),
        PackageEntry(path: 'data/app.so', offset: 10, compressedSize: 10, size: 20, sha256: 'b' * 64),
      ],
);

void main() {
  test('nomes de aplicação', () {
    expect(validateAppName('Meu App'), isNull);
    expect(validateAppName(''), isNotNull);
    expect(validateAppName('CON'), isNotNull);
    expect(validateAppName('a/b'), isNotNull);
    expect(validateAppName('..'), isNotNull);
    expect(validateAppName('App.'), isNotNull);
    expect(validateAppName('Common Files'), isNotNull);
  });

  test('caminhos relativos maliciosos são rejeitados', () {
    expect(validateRelativePath('data/app.so'), isNull);
    for (final bad in ['../x', 'data/../../x', '/abs', r'C:\x', 'C:/x', 'a\\b', 'a//b', 'x:ads', 'nul.txt']) {
      expect(validateRelativePath(bad), isNotNull, reason: bad);
    }
  });

  test('manifesto valida limites e caminhos', () {
    _manifest().validate(20);
    expect(() => _manifest().validate(15), throwsA(isA<PackageFormatException>()));
    expect(
      () => _manifest(
        files: [
          PackageEntry(path: 'meu_app.exe', offset: 0, compressedSize: 1, size: 1, sha256: 'a' * 64),
          PackageEntry(path: 'data/../../evil.dll', offset: 0, compressedSize: 1, size: 1, sha256: 'a' * 64),
        ],
      ).validate(10),
      throwsA(isA<PackageFormatException>()),
    );
    expect(() => _manifest(dirs: []).validate(20), throwsA(isA<PackageFormatException>()));
  });

  test('trailer exige layout contíguo', () {
    final trailer = PackageTrailer(
      payloadOffset: 100,
      payloadLength: 50,
      manifestOffset: 150,
      manifestLength: 10,
      manifestSha256: List.filled(32, 1),
    );
    final bytes = trailer.encode();
    expect(PackageTrailer.decode(bytes, 160 + trailerSize).payloadLength, 50);
    expect(() => PackageTrailer.decode(bytes, 999), throwsA(isA<PackageFormatException>()));
  });
}
