import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/names.dart';
import '../packer/build_inspector.dart';
import '../packer/packer.dart';
import 'theme.dart';
import 'widgets.dart';

const _launcherAsset = 'assets/launcher/pack_forge_launcher.exe';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _appName = TextEditingController();
  final _fileName = TextEditingController();

  String _buildDir = '';
  BuildInspection? _inspection;
  bool _inspecting = false;
  String? _mainExecutable;
  String? _iconPath;
  String _outputDir = '';
  bool _fileNameEdited = false;

  bool _packing = false;
  String _stage = '';
  double? _fraction;
  PackResult? _result;
  String? _error;

  @override
  void dispose() {
    _appName.dispose();
    _fileName.dispose();
    super.dispose();
  }

  Future<void> _selectBuildDir() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Selecionar build');
    if (dir == null) return;
    setState(() {
      _buildDir = dir;
      _inspection = null;
      _inspecting = true;
      _mainExecutable = null;
      _result = null;
      _error = null;
    });
    final inspection = await inspectBuildInBackground(dir);
    if (!mounted || _buildDir != dir) return;
    setState(() {
      _inspecting = false;
      _inspection = inspection;
      if (inspection.executables.isNotEmpty) {
        _mainExecutable = inspection.executables.first;
        if (_appName.text.isEmpty) {
          _appName.text = p.basenameWithoutExtension(_mainExecutable!);
          _syncFileName();
        }
      }
      _iconPath ??= inspection.suggestedIcon;
    });
  }

  Future<void> _selectIcon() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Ícone', extensions: ['ico']),
      ],
      confirmButtonText: 'Selecionar ícone',
    );
    if (file != null) setState(() => _iconPath = file.path);
  }

  Future<void> _selectOutputDir() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Salvar aqui');
    if (dir != null) setState(() => _outputDir = dir);
  }

  void _syncFileName() {
    if (!_fileNameEdited) _fileName.text = '${_appName.text.trim()}-setup.exe';
  }

  Future<void> _generate() async {
    setState(() {
      _result = null;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final appName = _appName.text;
    final fileName = _fileName.text;
    final validation = validateRequest(
      buildDir: _buildDir,
      mainExecutable: _mainExecutable,
      appName: appName,
      outputDir: _outputDir,
      outputFileName: fileName,
      iconPath: _iconPath,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (_inspection?.isValid != true) {
      setState(() => _error = 'A pasta da build selecionada não é válida.');
      return;
    }

    final outputPath = p.join(_outputDir, fileName);
    if (File(outputPath).existsSync() && !await _confirmOverwrite(outputPath)) return;

    final Uint8List launcher;
    try {
      launcher = (await rootBundle.load(_launcherAsset)).buffer.asUint8List();
    } on Exception {
      setState(
        () => _error =
            'O launcher não foi encontrado nos recursos do Pack Forge. '
            'Execute "dart run tool/build_launcher.dart" e gere o Pack Forge novamente.',
      );
      return;
    }

    setState(() {
      _packing = true;
      _stage = 'Iniciando...';
      _fraction = null;
    });
    try {
      final result = await createPackage(
        PackRequest(
          buildDir: _buildDir,
          mainExecutable: _mainExecutable!,
          appName: appName,
          outputPath: outputPath,
          iconPath: _iconPath,
          launcherBytes: launcher,
        ),
        (stage, fraction) {
          if (mounted) {
            setState(() {
              _stage = stage;
              _fraction = fraction;
            });
          }
        },
      );
      if (mounted) setState(() => _result = result);
    } on PackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Erro inesperado ao gerar o executável: $e');
    } finally {
      if (mounted) setState(() => _packing = false);
    }
  }

  Future<bool> _confirmOverwrite(String path) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Substituir arquivo?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Já existe um arquivo com esse nome:'),
              const SizedBox(height: 8),
              Text(path, style: AppText.mono.copyWith(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Substituir')),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _TopBar(),
          Expanded(
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 960;
                  final form = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInputStep(),
                      const SizedBox(height: 16),
                      _buildIdentityStep(),
                      const SizedBox(height: 16),
                      _buildOutputStep(),
                    ],
                  );
                  final summary = _buildSummary();
                  return Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Empacotar aplicação', style: AppText.headline),
                              const SizedBox(height: 6),
                              const Text(
                                'Gere um instalador único (.exe) a partir de uma build release '
                                'do Flutter Windows.',
                                style: AppText.bodySubtle,
                              ),
                              const SizedBox(height: 28),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: form),
                                    const SizedBox(width: 20),
                                    SizedBox(width: 360, child: summary),
                                  ],
                                )
                              else ...[
                                form,
                                const SizedBox(height: 16),
                                summary,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputStep() {
    final inspection = _inspection;
    final Widget? status = _inspecting
        ? const StatusBadge('Analisando...', tone: BadgeTone.accent, dot: true)
        : inspection == null
        ? null
        : inspection.isValid
        ? const StatusBadge('Build válida', tone: BadgeTone.success, dot: true)
        : const StatusBadge('Build inválida', tone: BadgeTone.danger, dot: true);

    return StepPanel(
      step: 1,
      eyebrow: 'Entrada',
      title: 'Build do Flutter',
      description: 'Pasta gerada por flutter build windows --release.',
      trailing: status,
      children: [
        FieldGroup(
          label: 'Pasta da build',
          caption: const Text(r'Ex.: build\windows\x64\runner\Release', style: AppText.caption),
          child: PathField(
            value: _buildDir,
            placeholder: 'Nenhuma pasta selecionada',
            icon: Icons.folder_outlined,
            buttonLabel: 'Selecionar',
            onPick: _packing ? null : _selectBuildDir,
          ),
        ),
        if (_inspecting) const LinearProgressIndicator(),
        if (inspection != null && !inspection.isValid)
          Notice(title: 'Esta pasta não pode ser empacotada', lines: inspection.errors),
        if (inspection != null && inspection.isValid) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge('${inspection.fileCount} arquivos'),
              StatusBadge(_formatBytes(inspection.totalBytes)),
              const StatusBadge('Windows x64'),
            ],
          ),
          FieldGroup(
            label: 'Executável principal',
            caption: const Text(
              'Iniciado após a instalação e usado pelo atalho da área de trabalho.',
              style: AppText.caption,
            ),
            child: Column(
              children: [
                for (final exe in inspection.executables) ...[
                  SelectableRow(
                    title: exe,
                    selected: exe == _mainExecutable,
                    onTap: _packing ? null : () => setState(() => _mainExecutable = exe),
                    trailing: exe == _mainExecutable
                        ? const StatusBadge('principal', tone: BadgeTone.accent)
                        : null,
                  ),
                  if (exe != inspection.executables.last) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIdentityStep() {
    return StepPanel(
      step: 2,
      eyebrow: 'Pacote',
      title: 'Identidade',
      description: 'O nome define a pasta de instalação e o atalho.',
      children: [
        FieldGroup(
          label: 'Nome da aplicação',
          child: TextFormField(
            controller: _appName,
            enabled: !_packing,
            style: AppText.body,
            decoration: const InputDecoration(hintText: 'Ex.: Meu App'),
            onChanged: (_) => setState(_syncFileName),
            validator: (value) => validateAppName(value ?? ''),
          ),
        ),
        FieldGroup(
          label: 'Ícone do instalador',
          caption: const Text('Opcional. Arquivo .ico aplicado ao executável gerado.', style: AppText.caption),
          child: PathField(
            value: _iconPath ?? '',
            placeholder: 'Ícone padrão',
            icon: Icons.image_outlined,
            buttonLabel: 'Selecionar',
            leading: _iconPath == null ? null : _IconPreview(path: _iconPath!),
            onPick: _packing ? null : _selectIcon,
            onClear: _packing ? null : () => setState(() => _iconPath = null),
          ),
        ),
      ],
    );
  }

  Widget _buildOutputStep() {
    return StepPanel(
      step: 3,
      eyebrow: 'Saída',
      title: 'Destino',
      description: 'Onde o executável único será salvo.',
      children: [
        FieldGroup(
          label: 'Nome do arquivo final',
          child: TextFormField(
            controller: _fileName,
            enabled: !_packing,
            style: AppText.mono,
            decoration: const InputDecoration(hintText: 'meu_app-setup.exe'),
            onChanged: (_) => setState(() => _fileNameEdited = true),
            validator: (value) => validateOutputFileName(value ?? ''),
          ),
        ),
        FieldGroup(
          label: 'Pasta de saída',
          child: PathField(
            value: _outputDir,
            placeholder: 'Nenhuma pasta selecionada',
            icon: Icons.drive_folder_upload_outlined,
            buttonLabel: 'Selecionar',
            onPick: _packing ? null : _selectOutputDir,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final appName = _appName.text.trim();
    final validBuild = _inspection?.isValid == true;
    final fileName = _fileName.text.trim();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('RESUMO', style: AppText.eyebrow),
          const SizedBox(height: 6),
          const Text('O que será gerado', style: AppText.cardTitle),
          const SizedBox(height: 12),
          SummaryRow(label: 'Aplicação', value: appName),
          const Divider(height: 1),
          SummaryRow(label: 'Executável', value: _mainExecutable, mono: true),
          const Divider(height: 1),
          SummaryRow(
            label: 'Instala em',
            value: appName.isEmpty ? null : 'C:\\Program Files\\$appName\\',
            mono: true,
          ),
          const Divider(height: 1),
          SummaryRow(label: 'Atalho', value: appName.isEmpty ? null : 'Área de trabalho › $appName'),
          const Divider(height: 1),
          SummaryRow(label: 'Arquivo', value: fileName, mono: true, singleLine: true),
          const Divider(height: 1),
          SummaryRow(label: 'Salvo em', value: _outputDir, mono: true, singleLine: true),
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: _packing || !validBuild ? null : _generate,
              child: Text(_packing ? 'Gerando...' : 'Gerar executável'),
            ),
          ),
          if (!validBuild && !_packing) ...[
            const SizedBox(height: 8),
            const Text(
              'Selecione uma build válida para continuar.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ],
          if (_packing) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: _fraction),
            ),
            const SizedBox(height: 8),
            Text(
              _stage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.mono.copyWith(fontSize: 12, color: AppColors.inkSubtle),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Notice(title: 'Não foi possível gerar o executável', lines: [_error!]),
          ],
          if (_result != null) ...[const SizedBox(height: 16), _ResultPanel(result: _result!)],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.inventory_2_rounded, size: 14, color: AppColors.onPrimary),
          ),
          const SizedBox(width: 10),
          const Text(
            'Pack Forge',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Empacotador Flutter Windows', style: AppText.caption),
          const Spacer(),
          const StatusBadge('x64'),
        ],
      ),
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Image.file(
        File(path),
        width: 18,
        height: 18,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_outlined, size: 16, color: AppColors.inkTertiary),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final PackResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              Text('Executável gerado', style: AppText.label.copyWith(color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 10),
          Tooltip(
            message: result.outputPath,
            waitDuration: const Duration(milliseconds: 500),
            child: Text(
              p.basename(result.outputPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.mono.copyWith(fontSize: 12, color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge('${result.fileCount} arquivos'),
              StatusBadge('${_formatBytes(result.originalBytes)} → ${_formatBytes(result.packageBytes)}'),
              StatusBadge('build ${result.buildId}'),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Process.run('explorer.exe', ['/select,', result.outputPath]),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Mostrar na pasta'),
          ),
        ],
      ),
    );
  }
}
