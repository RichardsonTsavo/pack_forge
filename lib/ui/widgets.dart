import 'package:flutter/material.dart';

import 'theme.dart';

/// Painel elevado sobre o canvas (surface-1 + borda fina).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}

/// Etapa numerada do formulário.
class StepPanel extends StatelessWidget {
  const StepPanel({
    super.key,
    required this.step,
    required this.eyebrow,
    required this.title,
    this.description,
    this.trailing,
    required this.children,
  });

  final int step;
  final String eyebrow;
  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${step.toString().padLeft(2, '0')} · ${eyebrow.toUpperCase()}', style: AppText.eyebrow),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: AppText.cardTitle),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: AppText.bodySubtle),
          ],
          for (final child in children) ...[const SizedBox(height: 20), child],
        ],
      ),
    );
  }
}

/// Rótulo acima do campo, com legenda opcional abaixo.
class FieldGroup extends StatelessWidget {
  const FieldGroup({super.key, required this.label, required this.child, this.caption});

  final String label;
  final Widget child;
  final Widget? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 8),
        child,
        if (caption != null) ...[const SizedBox(height: 6), caption!],
      ],
    );
  }
}

/// Exibe um caminho em fonte mono com o botão de seleção ao lado.
class PathField extends StatelessWidget {
  const PathField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.buttonLabel,
    required this.onPick,
    this.onClear,
    this.leading,
  });

  final String value;
  final String placeholder;
  final IconData icon;
  final String buttonLabel;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final empty = value.isEmpty;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                leading ?? Icon(icon, size: 16, color: AppColors.inkTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: empty ? '' : value,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      empty ? placeholder : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: empty
                          ? AppText.body.copyWith(color: AppColors.inkTertiary)
                          : AppText.mono,
                    ),
                  ),
                ),
                if (onClear != null && !empty)
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'Remover',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: OutlinedButton(onPressed: onPick, child: Text(buttonLabel)),
        ),
      ],
    );
  }
}

enum BadgeTone { neutral, success, danger, accent }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.tone = BadgeTone.neutral, this.dot = false});

  final String text;
  final BadgeTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      BadgeTone.neutral => AppColors.inkSubtle,
      BadgeTone.success => AppColors.success,
      BadgeTone.danger => AppColors.danger,
      BadgeTone.accent => AppColors.primaryHover,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: AppText.caption.copyWith(
              color: tone == BadgeTone.neutral ? AppColors.inkMuted : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha selecionável (estilo lista) usada para escolher o executável.
class SelectableRow extends StatelessWidget {
  const SelectableRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    this.trailing,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary.withValues(alpha: 0.6) : AppColors.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.hairlineTertiary,
                    width: selected ? 4 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppText.mono)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensagem de erro ou aviso com faixa lateral colorida.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.title, required this.lines, this.tone = BadgeTone.danger});

  final String title;
  final List<String> lines;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == BadgeTone.success ? AppColors.success : AppColors.danger;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              tone == BadgeTone.success ? Icons.check_circle_rounded : Icons.error_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.label.copyWith(color: AppColors.ink)),
                for (final line in lines) ...[
                  const SizedBox(height: 4),
                  SelectableText(line, style: AppText.bodySubtle.copyWith(fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha chave/valor do painel de resumo.
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.singleLine = false,
  });

  final String label;
  final String? value;
  final bool mono;

  /// Trunca o valor em uma linha e mostra o texto completo no tooltip.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final missing = value == null || value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: AppText.caption)),
          Expanded(
            child: Tooltip(
              message: singleLine && !missing ? value! : '',
              waitDuration: const Duration(milliseconds: 500),
              child: Text(
                missing ? '—' : value!,
                maxLines: singleLine ? 1 : null,
                overflow: singleLine ? TextOverflow.ellipsis : null,
                style: missing
                    ? AppText.caption.copyWith(color: AppColors.inkTertiary)
                    : (mono
                          ? AppText.mono.copyWith(fontSize: 12)
                          : AppText.body.copyWith(fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
