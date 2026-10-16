// Compila o launcher autoextrator e o copia para os assets do Pack Forge.
//
//   dart run tool/build_launcher.dart
//
// Etapas: dart compile exe -> substitui os recursos por um manifest (asInvoker,
// Common Controls v6, DPI) -> subsistema GUI (sem console) -> assets/launcher.

import 'dart:io';

import 'package:pack_forge/core/pe.dart';
import 'package:path/path.dart' as p;

const _manifest = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0"
        processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
    </dependentAssembly>
  </dependency>
</assembly>
''';

Future<void> main() async {
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final buildDir = Directory(p.join(root, 'build', 'launcher'))..createSync(recursive: true);
  final compiled = p.join(buildDir.path, 'pack_forge_launcher.exe');
  final asset = p.join(root, 'assets', 'launcher', 'pack_forge_launcher.exe');

  stdout.writeln('Compilando launcher...');
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    p.join(root, 'launcher', 'launcher.dart'),
    '-o',
    compiled,
  ], workingDirectory: root);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    stderr.writeln('Falha ao compilar o launcher.');
    exit(result.exitCode);
  }

  replaceResourcesWithManifest(compiled, _manifest);
  setGuiSubsystem(compiled);
  if (readPeMachine(compiled) != imageFileMachineAmd64) {
    stderr.writeln('O launcher gerado não é x64.');
    exit(1);
  }

  Directory(p.dirname(asset)).createSync(recursive: true);
  File(compiled).copySync(asset);
  stdout.writeln('Launcher atualizado: $asset (${File(asset).lengthSync()} bytes)');
}
