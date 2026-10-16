// Chamadas Win32 usadas pelo launcher: diálogos, elevação via UAC, processos,
// pastas conhecidas e atalhos.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

const int _wmUser = 0x0400;
const int _tdmClickButton = _wmUser + 102;
const int _tdmSetProgressBarMarquee = _wmUser + 107;
const int _tdmEnableButton = _wmUser + 111;
const int _tdnCreated = 0;
const int _tdnButtonClicked = 2;
const int _tdnTimer = 4;
const int _seeMaskNoCloseProcess = 0x00000040;
const int _seeMaskNoAsync = 0x00000100;
const int _slgpRawPath = 0x4;
const int _waitTimeout = 258;

/// Resultado de diálogo quando o usuário fecha a janela ou pressiona Esc.
const int dialogCancelled = 2; // IDCANCEL

enum DialogIcon { none, info, warning, error, shield }

PCWSTR? _icon(DialogIcon icon) => switch (icon) {
  DialogIcon.none => null,
  DialogIcon.info => TD_INFORMATION_ICON,
  DialogIcon.warning => TD_WARNING_ICON,
  DialogIcon.error => TD_ERROR_ICON,
  DialogIcon.shield => TD_SHIELD_ICON,
};

/// Exibe um TaskDialog nativo e retorna o id do botão escolhido.
///
/// [buttons] são botões personalizados (id, texto). Sem botões, mostra "OK".
/// Os ids devem ser maiores que 100 para não colidir com [dialogCancelled].
int showDialog({
  required String title,
  required String instruction,
  String? content,
  List<(int, String)> buttons = const [],
  int? defaultButton,
  DialogIcon icon = DialogIcon.none,
  String? details,
}) {
  return using((arena) {
    final config = arena<TASKDIALOGCONFIG>();
    final c = config.ref
      ..cbSize = sizeOf<TASKDIALOGCONFIG>()
      ..dwFlags = TASKDIALOG_FLAGS(TDF_ALLOW_DIALOG_CANCELLATION | TDF_SIZE_TO_CONTENT)
      ..pszWindowTitle = arena.pwstr(title)
      ..pszMainInstruction = arena.pwstr(instruction);
    if (content != null) c.pszContent = arena.pwstr(content);
    final iconRes = _icon(icon);
    if (iconRes != null) c.pszMainIcon = PWSTR(iconRes);
    if (details != null && details.isNotEmpty) {
      c
        ..pszExpandedInformation = arena.pwstr(details)
        ..pszCollapsedControlText = arena.pwstr('Mostrar detalhes')
        ..pszExpandedControlText = arena.pwstr('Ocultar detalhes');
    }
    if (buttons.isEmpty) {
      c.dwCommonButtons = TDCBF_OK_BUTTON;
    } else {
      final native = arena<TASKDIALOG_BUTTON>(buttons.length);
      for (var i = 0; i < buttons.length; i++) {
        native[i]
          ..nButtonID = buttons[i].$1
          ..pszButtonText = arena.pwstr(buttons[i].$2);
      }
      c
        ..cButtons = buttons.length
        ..pButtons = native
        ..nDefaultButton = defaultButton ?? buttons.first.$1;
    }
    final pressed = arena<Int32>();
    TaskDialogIndirect(config, pressed, null, null);
    return pressed.value;
  });
}

/// Mostra um diálogo de progresso (barra marquee) enquanto [process] executa.
///
/// O diálogo não pode ser fechado pelo usuário; ele fecha sozinho quando o
/// processo termina.
void showProgressUntilExit({
  required String title,
  required String instruction,
  required String content,
  required HANDLE process,
}) {
  var finished = false;

  int callback(Pointer hwnd, int msg, int wParam, int lParam, int refData) {
    final window = HWND(hwnd);
    switch (msg) {
      case _tdnCreated:
        SendMessage(window, _tdmSetProgressBarMarquee, WPARAM(1), LPARAM(30));
        SendMessage(window, _tdmEnableButton, WPARAM(IDOK), LPARAM(0));
      case _tdnTimer:
        if (!finished && WaitForSingleObject(process, 0).value != _waitTimeout) {
          finished = true;
          SendMessage(window, _tdmEnableButton, WPARAM(IDOK), LPARAM(1));
          SendMessage(window, _tdmClickButton, WPARAM(IDOK), LPARAM(0));
        }
      case _tdnButtonClicked:
        return finished ? 0 : 1; // S_FALSE mantém o diálogo aberto.
    }
    return 0;
  }

  final native = NativeCallable<PFTASKDIALOGCALLBACK>.isolateLocal(
    callback,
    exceptionalReturn: 0,
  );
  try {
    using((arena) {
      final config = arena<TASKDIALOGCONFIG>();
      config.ref
        ..cbSize = sizeOf<TASKDIALOGCONFIG>()
        ..dwFlags = TASKDIALOG_FLAGS(TDF_SHOW_MARQUEE_PROGRESS_BAR | TDF_CALLBACK_TIMER)
        ..dwCommonButtons = TDCBF_OK_BUTTON
        ..pszWindowTitle = arena.pwstr(title)
        ..pszMainInstruction = arena.pwstr(instruction)
        ..pszContent = arena.pwstr(content)
        ..pfCallback = native.nativeFunction;
      TaskDialogIndirect(config, null, null, null);
    });
  } finally {
    native.close();
  }
  // Garante que o processo terminou mesmo se o diálogo fechar por outro motivo.
  WaitForSingleObject(process, INFINITE);
}

sealed class ElevatedLaunch {}

class ElevatedStarted extends ElevatedLaunch {
  ElevatedStarted(this.process);

  final HANDLE process;
}

class ElevatedDenied extends ElevatedLaunch {}

class ElevatedFailed extends ElevatedLaunch {
  ElevatedFailed(this.error);

  final int error;
}

/// Executa [file] como administrador (UAC) e retorna o handle do processo.
ElevatedLaunch startElevated(String file, String parameters) {
  return using((arena) {
    final info = arena<SHELLEXECUTEINFO>();
    info.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNoCloseProcess | _seeMaskNoAsync
      ..lpVerb = arena.pwstr('runas')
      ..lpFile = arena.pwstr(file)
      ..lpParameters = arena.pwstr(parameters)
      ..nShow = SW_HIDE;
    final result = ShellExecuteEx(info);
    if (!result.value) {
      if (result.error == ERROR_CANCELLED) return ElevatedDenied();
      return ElevatedFailed(result.error);
    }
    final process = info.ref.hProcess;
    if (process.address == 0) return ElevatedFailed(0);
    return ElevatedStarted(process);
  });
}

int exitCodeOf(HANDLE process) {
  return using((arena) {
    final code = arena<Uint32>();
    GetExitCodeProcess(process, code);
    CloseHandle(process);
    return code.value;
  });
}

/// Pastas conhecidas resolvidas pelo Windows (respeita redirecionamentos,
/// como a área de trabalho no OneDrive).
String programFilesPath() => _knownFolder(FOLDERID_ProgramFiles);

String desktopPath() => _knownFolder(FOLDERID_Desktop);

String programDataPath() => _knownFolder(FOLDERID_ProgramData);

String _knownFolder(GUID id) {
  return using((arena) {
    final path = SHGetKnownFolderPath(id.toNative(allocator: arena), KF_FLAG_DEFAULT, null);
    try {
      return path.toDartString();
    } finally {
      CoTaskMemFree(path);
    }
  });
}

/// Lista os caminhos dos executáveis em execução dentro de [directory].
///
/// Processos que o usuário atual não pode consultar são ignorados; o worker
/// elevado repete a verificação com mais permissões.
List<String> runningProcessesIn(String directory) {
  return using((arena) {
    const capacity = 4096;
    final pids = arena<Uint32>(capacity);
    final needed = arena<Uint32>();
    if (!EnumProcesses(pids, capacity * sizeOf<Uint32>(), needed).value) return const [];
    final count = needed.value ~/ sizeOf<Uint32>();
    final buffer = arena.pwstrBuffer(1024);
    final size = arena<Uint32>();
    final found = <String>[];
    for (var i = 0; i < count; i++) {
      final process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pids[i]).value;
      if (process.address == 0) continue;
      size.value = 1024;
      if (QueryFullProcessImageName(process, PROCESS_NAME_WIN32, buffer, size).value) {
        final image = buffer.toDartString(length: size.value);
        if (p.windows.isWithin(directory, image)) found.add(image);
      }
      CloseHandle(process);
    }
    return found;
  });
}

void _withCom(void Function(Arena arena) action) {
  CoInitializeEx(COINIT_APARTMENTTHREADED);
  try {
    using(action);
  } finally {
    CoUninitialize();
  }
}

/// Lê o alvo de um atalho .lnk, ou `null` se não for possível.
String? shortcutTarget(String lnkPath) {
  String? target;
  try {
    _withCom((arena) {
      final link = arena.com<IShellLink>(ShellLink);
      final file = arena.adopt(link.queryInterface<IPersistFile>());
      file.load(arena.pcwstr(lnkPath), STGM_READ);
      final buffer = arena.pwstrBuffer(1024);
      link.getPath(buffer, 1024, nullptr, _slgpRawPath);
      target = buffer.toDartString();
    });
  } on Exception {
    return null;
  }
  return target;
}

void createShortcut({
  required String lnkPath,
  required String target,
  required String workingDirectory,
  required String description,
}) {
  _withCom((arena) {
    final link = arena.com<IShellLink>(ShellLink);
    link
      ..setPath(arena.pcwstr(target))
      ..setWorkingDirectory(arena.pcwstr(workingDirectory))
      ..setDescription(arena.pcwstr(description))
      ..setIconLocation(arena.pcwstr(target), 0);
    final file = arena.adopt(link.queryInterface<IPersistFile>());
    file.save(arena.pcwstr(lnkPath), true);
  });
}

void setHidden(String path, bool hidden) {
  using((arena) {
    SetFileAttributes(
      arena.pcwstr(path),
      hidden ? FILE_ATTRIBUTE_HIDDEN : FILE_ATTRIBUTE_NORMAL,
    );
  });
}
