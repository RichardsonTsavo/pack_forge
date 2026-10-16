// Ponto de entrada do launcher autoextrator.
//
// Compilado com `dart run tool/build_launcher.dart`. O mesmo executável roda em
// dois modos:
//   - sem argumentos: interface do instalador (sem elevação);
//   - `--pkforge-worker <operação>`: operações de arquivo, elevado via UAC.

import 'dart:io';

import 'package:pack_forge/core/package_format.dart';

import 'src/installer_ui.dart';
import 'src/layout.dart';
import 'src/win.dart';
import 'src/worker.dart';

InstallLayout _layoutFor(PackageManifest manifest) => InstallLayout(
  programFiles: programFilesPath(),
  programData: programDataPath(),
  appName: manifest.appName,
  mainExecutable: manifest.mainExecutable,
);

void main(List<String> args) {
  if (args.isNotEmpty && args.first == workerFlag) {
    exit(args.length == 2 ? runWorker(args[1], _layoutFor) : WorkerCode.badArguments);
  }
  var code = 1;
  try {
    code = runInstallerUi(_layoutFor);
  } on Object catch (e) {
    try {
      showDialog(
        title: 'Instalador',
        instruction: 'Ocorreu um erro inesperado.',
        content: 'Nenhuma aplicação foi iniciada.',
        icon: DialogIcon.error,
        details: e.toString(),
      );
    } on Object {
      // Sem interface disponível.
    }
  }
  exit(code);
}
