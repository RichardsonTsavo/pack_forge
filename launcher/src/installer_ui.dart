// Modo interface: roda sem elevação. Mostra os diálogos, solicita o UAC apenas
// para o worker, cria/remove o atalho do usuário atual e inicia a aplicação.

import 'dart:io';

import 'package:pack_forge/core/package_format.dart';
import 'package:path/path.dart' as p;

import 'layout.dart';
import 'win.dart';
import 'worker.dart';

final p.Context _win = p.windows;

const int _btnInstall = 101;
const int _btnUpdate = 102;
const int _btnUninstall = 103;
const int _btnCancel = 104;
const int _btnRetry = 105;
const int _btnOpen = 106;

int runInstallerUi(InstallLayout Function(PackageManifest) layoutFor) {
  final self = Platform.resolvedExecutable;

  final PackageManifest manifest;
  try {
    final package = PackageReader.open(self);
    manifest = package.manifest;
    package.close();
  } on PackageFormatException catch (e) {
    _error('Pacote inválido', 'Não foi possível ler este instalador.', e.message);
    return 1;
  } on FileSystemException catch (e) {
    _error('Pacote inválido', 'Não foi possível ler este instalador.', e.toString());
    return 1;
  }

  final layout = layoutFor(manifest);
  final appName = manifest.appName;

  // O instalador não pode remover a pasta de onde ele mesmo está rodando:
  // nesse caso ele se copia para a pasta temporária e reinicia de lá.
  if (_win.isWithin(layout.installDir, self)) {
    return _relaunchFromTemp(self, layout);
  }

  final uiLock = _acquireUiLock(layout);
  if (uiLock == null) {
    _error(appName, 'O instalador de $appName já está aberto.', null);
    return 1;
  }
  try {
    if (!Directory(layout.installDir).existsSync()) {
      return _installFlow(self, layout);
    }
    return _maintenanceFlow(self, layout);
  } finally {
    uiLock.closeSync();
  }
}

int _installFlow(String self, InstallLayout layout) {
  final appName = layout.appName;
  final choice = showDialog(
    title: 'Instalar $appName',
    instruction: 'Instalar $appName neste computador?',
    content:
        'A aplicação será instalada em:\n${layout.installDir}\n\n'
        'Será criado um atalho na sua área de trabalho. '
        'O Windows pedirá permissão de administrador.',
    buttons: [(_btnInstall, 'Instalar'), (_btnCancel, 'Cancelar')],
    icon: DialogIcon.shield,
  );
  if (choice != _btnInstall) return 0;

  final ok = _runElevated(
    self,
    layout,
    WorkerOperation.install,
    title: 'Instalar $appName',
    progress: 'Instalando $appName...',
  );
  if (!ok) return 1;
  _finishInstalled(layout, updated: false);
  return 0;
}

int _maintenanceFlow(String self, InstallLayout layout) {
  final appName = layout.appName;
  if (!File(layout.installedExecutable).existsSync()) {
    _error(
      appName,
      'A pasta de instalação não pertence a esta aplicação.',
      'A pasta ${layout.installDir} existe, mas não contém ${layout.mainExecutable}. '
          'Ela pode pertencer a outro programa, por isso nada foi alterado.',
    );
    return 1;
  }

  final choice = showDialog(
    title: 'Atualização da aplicação',
    instruction: 'Uma instalação desta aplicação foi encontrada neste computador.',
    content: 'Deseja atualizar para a nova versão?\n\nLocal: ${layout.installDir}',
    buttons: [
      (_btnUpdate, 'Atualizar'),
      (_btnUninstall, 'Desinstalar'),
      (_btnCancel, 'Cancelar'),
    ],
    icon: DialogIcon.info,
  );

  switch (choice) {
    case _btnUpdate:
      if (!_waitUntilClosed(layout)) return 0;
      final ok = _runElevated(
        self,
        layout,
        WorkerOperation.update,
        title: 'Atualização da aplicação',
        progress: 'Atualizando $appName...',
      );
      if (!ok) return 1;
      _finishInstalled(layout, updated: true);
      return 0;

    case _btnUninstall:
      final confirm = showDialog(
        title: 'Desinstalar aplicação',
        instruction: 'Deseja realmente desinstalar esta aplicação?',
        content:
            'A pasta de instalação e seus arquivos serão removidos:\n${layout.installDir}',
        buttons: [(_btnUninstall, 'Desinstalar'), (_btnCancel, 'Cancelar')],
        defaultButton: _btnCancel,
        icon: DialogIcon.warning,
      );
      if (confirm != _btnUninstall) return 0;
      if (!_waitUntilClosed(layout)) return 0;
      final ok = _runElevated(
        self,
        layout,
        WorkerOperation.uninstall,
        title: 'Desinstalar aplicação',
        progress: 'Removendo $appName...',
        acceptPartial: true,
      );
      if (!ok) return 1;
      final shortcutRemoved = _removeShortcut(layout);
      showDialog(
        title: 'Desinstalar aplicação',
        instruction: '$appName foi desinstalado.',
        content: shortcutRemoved
            ? null
            : 'O atalho da área de trabalho não foi encontrado ou não apontava para esta instalação, '
                  'por isso não foi alterado.',
        icon: DialogIcon.info,
      );
      return 0;

    default:
      return 0;
  }
}

/// Pede para o usuário fechar a aplicação enquanto ela estiver em execução.
bool _waitUntilClosed(InstallLayout layout) {
  while (true) {
    final running = runningProcessesIn(layout.installDir);
    if (running.isEmpty) return true;
    final choice = showDialog(
      title: layout.appName,
      instruction: '${layout.appName} está em execução.',
      content: 'Feche a aplicação antes de continuar e clique em "Tentar novamente".',
      buttons: [(_btnRetry, 'Tentar novamente'), (_btnCancel, 'Cancelar')],
      icon: DialogIcon.warning,
      details: running.join('\n'),
    );
    if (choice != _btnRetry) return false;
  }
}

bool _runElevated(
  String self,
  InstallLayout layout,
  WorkerOperation operation, {
  required String title,
  required String progress,
  bool acceptPartial = false,
}) {
  switch (startElevated(self, '$workerFlag ${operation.name}')) {
    case ElevatedDenied():
      _error(title, 'Operação cancelada.', 'A permissão de administrador não foi concedida. Nada foi alterado.');
      return false;
    case ElevatedFailed(:final error):
      _error(title, 'Não foi possível solicitar permissão de administrador.', 'Erro do Windows: $error');
      return false;
    case ElevatedStarted(:final process):
      showProgressUntilExit(
        title: title,
        instruction: progress,
        content: 'Aguarde, isso pode levar alguns instantes.',
        process: process,
      );
      final code = exitCodeOf(process);
      if (code == WorkerCode.ok) return true;
      final details = _readLastError(layout);
      if (acceptPartial && code == WorkerCode.partialUninstall) {
        showDialog(
          title: title,
          instruction: 'A desinstalação foi concluída com pendências.',
          content: _messageFor(code, layout),
          icon: DialogIcon.warning,
          details: details,
        );
        return true;
      }
      _error(title, _headlineFor(operation), _messageFor(code, layout), details);
      return false;
  }
}

void _finishInstalled(InstallLayout layout, {required bool updated}) {
  final appName = layout.appName;
  final shortcutWarning = _ensureShortcut(layout);
  final details = [
    'Local: ${layout.installDir}',
    shortcutWarning ?? 'Atalho criado na área de trabalho: $appName.',
  ].join('\n\n');
  showDialog(
    title: updated ? 'Atualização da aplicação' : 'Instalar $appName',
    instruction: updated
        ? '$appName foi atualizado com sucesso.'
        : '$appName foi instalado com sucesso.',
    content: details,
    buttons: [(_btnOpen, 'Abrir $appName')],
    icon: shortcutWarning == null ? DialogIcon.info : DialogIcon.warning,
  );
  // A aplicação é iniciada ao fechar o aviso (pelo botão ou pelo X).
  try {
    Process.start(
      layout.installedExecutable,
      const [],
      workingDirectory: layout.installDir,
      mode: ProcessStartMode.detached,
    );
  } on ProcessException catch (e) {
    _error(
      layout.appName,
      'A aplicação foi instalada, mas não pôde ser iniciada.',
      e.message,
    );
  }
}

String _shortcutPath(InstallLayout layout) => _win.join(desktopPath(), '${layout.appName}.lnk');

/// Cria o atalho se não existir. Retorna um aviso quando não foi possível.
String? _ensureShortcut(InstallLayout layout) {
  try {
    final lnk = _shortcutPath(layout);
    if (File(lnk).existsSync()) {
      final target = shortcutTarget(lnk);
      if (target != null && _win.equals(target, layout.installedExecutable)) return null;
      return 'Já existe um atalho "${layout.appName}" na área de trabalho apontando para outro '
          'programa. Ele não foi substituído; o atalho desta aplicação não foi criado.';
    }
    createShortcut(
      lnkPath: lnk,
      target: layout.installedExecutable,
      workingDirectory: layout.installDir,
      description: layout.appName,
    );
    return null;
  } on Exception catch (e) {
    return 'Não foi possível criar o atalho na área de trabalho: $e';
  }
}

/// Remove o atalho apenas se ele apontar para esta instalação.
bool _removeShortcut(InstallLayout layout) {
  try {
    final lnk = _shortcutPath(layout);
    if (!File(lnk).existsSync()) return false;
    final target = shortcutTarget(lnk);
    if (target == null || !_win.equals(target, layout.installedExecutable)) return false;
    File(lnk).deleteSync();
    return true;
  } on Exception {
    return false;
  }
}

String _headlineFor(WorkerOperation operation) => switch (operation) {
  WorkerOperation.install => 'A instalação não foi concluída.',
  WorkerOperation.update => 'A atualização não foi concluída.',
  WorkerOperation.uninstall => 'A desinstalação não foi concluída.',
};

String _messageFor(int code, InstallLayout layout) => switch (code) {
  WorkerCode.invalidPackage || WorkerCode.integrityFailure =>
    'O pacote está corrompido ou incompleto. Gere o instalador novamente. '
        'A instalação existente não foi alterada.',
  WorkerCode.busy => 'Outra operação de ${layout.appName} já está em andamento. Aguarde e tente novamente.',
  WorkerCode.appRunning => '${layout.appName} está em execução. Feche a aplicação e tente novamente.',
  WorkerCode.filesInUse =>
    'Alguns arquivos da instalação estão em uso por outro programa. '
        'Feche a aplicação (ou programas que usem a pasta) e tente novamente. Nada foi alterado.',
  WorkerCode.notOwned =>
    'A pasta ${layout.installDir} não contém ${layout.mainExecutable}. Nada foi alterado.',
  WorkerCode.alreadyInstalled => 'A aplicação foi instalada por outro processo. Execute o instalador novamente.',
  WorkerCode.notInstalled => 'A instalação não foi encontrada. Execute o instalador novamente.',
  WorkerCode.accessDenied => 'Acesso negado ao gravar em ${layout.installDir}.',
  WorkerCode.partialUninstall =>
    'A aplicação foi removida, mas alguns arquivos temporários não puderam ser apagados. '
        'Eles serão removidos na próxima execução deste instalador.',
  WorkerCode.ioFailure => 'Falha ao gravar os arquivos. Verifique o espaço em disco e tente novamente.',
  _ => 'Ocorreu um erro inesperado (código $code).',
};

String? _readLastError(InstallLayout layout) {
  try {
    final file = File(layout.lastErrorFile);
    return file.existsSync() ? file.readAsStringSync() : null;
  } on FileSystemException {
    return null;
  }
}

/// Impede duas janelas do instalador da mesma aplicação ao mesmo tempo.
/// Retorna `null` se outra janela já estiver aberta.
RandomAccessFile? _acquireUiLock(InstallLayout layout) {
  final dir = Directory(_win.join(Directory.systemTemp.path, 'pack_forge'))
    ..createSync(recursive: true);
  final file = File(_win.join(dir.path, '${layout.appKey}.lock')).openSync(mode: FileMode.append);
  try {
    file.lockSync(FileLock.exclusive);
    return file;
  } on FileSystemException {
    file.closeSync();
    return null;
  }
}

int _relaunchFromTemp(String self, InstallLayout layout) {
  try {
    final dir = Directory(_win.join(Directory.systemTemp.path, 'pack_forge', randomHex(6)))
      ..createSync(recursive: true);
    final copy = File(self).copySync(_win.join(dir.path, _win.basename(self)));
    Process.start(copy.path, const [], mode: ProcessStartMode.detached);
    return 0;
  } on Exception catch (e) {
    _error(layout.appName, 'Não foi possível preparar o instalador.', e.toString());
    return 1;
  }
}

void _error(String title, String instruction, String? content, [String? details]) {
  showDialog(
    title: title,
    instruction: instruction,
    content: content,
    icon: DialogIcon.error,
    details: details,
  );
}
