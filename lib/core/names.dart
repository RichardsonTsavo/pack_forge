// Validação de nomes de aplicação, arquivos e caminhos relativos do pacote.
//
// Este arquivo é Dart puro: é usado tanto pelo empacotador (Flutter) quanto
// pelo launcher (dart compile exe). Toda função retorna `null` quando o valor
// é válido ou uma mensagem em português explicando o problema.

const int maxAppNameLength = 64;
const int maxFileNameLength = 120;
const int maxRelativePathLength = 200;

const _reservedDeviceNames = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

// Pastas de C:\Program Files que nunca podem ser usadas como instalação, já que
// a atualização e a desinstalação removem a pasta inteira.
const _blockedInstallFolders = {
  'common files',
  'microsoft',
  'microsoft office',
  'modifiablewindowsapps',
  'windows defender',
  'windows defender advanced threat protection',
  'windows mail',
  'windows media player',
  'windows nt',
  'windows photo viewer',
  'windows security',
  'windows sidebar',
  'windowsapps',
  'windowspowershell',
  'internet explorer',
  'dotnet',
  'uninstall information',
};

final _invalidChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Valida um único segmento de caminho do Windows (nome de arquivo ou pasta).
String? validatePathSegment(String segment, {int maxLength = 255}) {
  if (segment.isEmpty) return 'o nome está vazio';
  if (segment.length > maxLength) {
    return 'o nome excede $maxLength caracteres';
  }
  if (segment == '.' || segment == '..') return 'o nome "$segment" é reservado';
  if (_invalidChars.hasMatch(segment)) {
    return 'o nome "$segment" contém caracteres inválidos ( < > : " / \\ | ? * )';
  }
  if (segment.endsWith('.') || segment.endsWith(' ')) {
    return 'o nome "$segment" não pode terminar com ponto ou espaço';
  }
  if (segment.startsWith(' ')) {
    return 'o nome "$segment" não pode começar com espaço';
  }
  final base = segment.split('.').first.toUpperCase();
  if (_reservedDeviceNames.contains(base)) {
    return 'o nome "$segment" é reservado pelo Windows';
  }
  return null;
}

/// Valida o nome da aplicação, que também é o nome da pasta de instalação.
String? validateAppName(String name) {
  if (name.trim().isEmpty) return 'Informe o nome da aplicação.';
  if (name != name.trim()) {
    return 'O nome da aplicação não pode começar ou terminar com espaço.';
  }
  final error = validatePathSegment(name, maxLength: maxAppNameLength);
  if (error != null) return 'Nome da aplicação inválido: $error.';
  if (name.startsWith('.')) {
    return 'O nome da aplicação não pode começar com ponto.';
  }
  if (_blockedInstallFolders.contains(name.toLowerCase())) {
    return 'O nome "$name" corresponde a uma pasta do sistema e não pode ser usado.';
  }
  return null;
}

/// Valida o nome do arquivo .exe final (com a extensão).
String? validateOutputFileName(String name) {
  if (name.trim().isEmpty) return 'Informe o nome do arquivo final.';
  if (!name.toLowerCase().endsWith('.exe')) {
    return 'O nome do arquivo final deve terminar com .exe.';
  }
  if (name.length <= 4) return 'Informe um nome antes da extensão .exe.';
  final error = validatePathSegment(name, maxLength: maxFileNameLength);
  if (error != null) return 'Nome do arquivo final inválido: $error.';
  return null;
}

/// Valida um caminho relativo do pacote, sempre separado por '/'.
///
/// Rejeita caminhos absolutos, letras de unidade, `..`, fluxos alternativos
/// (`:`), nomes reservados e qualquer outra forma de sair da pasta de destino.
String? validateRelativePath(String path) {
  if (path.isEmpty) return 'caminho vazio';
  if (path.length > maxRelativePathLength) {
    return 'caminho "$path" excede $maxRelativePathLength caracteres';
  }
  if (path.contains('\\')) return 'caminho "$path" usa separador inválido';
  if (path.startsWith('/')) return 'caminho "$path" é absoluto';
  for (final segment in path.split('/')) {
    final error = validatePathSegment(segment);
    if (error != null) return 'caminho "$path" inválido: $error';
  }
  return null;
}

/// Valida o nome do executável principal: arquivo .exe na raiz do pacote.
String? validateMainExecutableName(String name) {
  if (!name.toLowerCase().endsWith('.exe')) {
    return 'o executável principal "$name" não é um arquivo .exe';
  }
  if (name.contains('/') || name.contains('\\')) {
    return 'o executável principal "$name" deve estar na raiz da build';
  }
  return validatePathSegment(name);
}
