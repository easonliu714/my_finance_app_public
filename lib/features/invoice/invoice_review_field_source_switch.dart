import 'package:flutter/material.dart';

enum InvoiceReviewFieldSourceSelection {
  local,
  ai,
  manual,
}

class InvoiceReviewFieldSourceSwitch extends StatelessWidget {
  const InvoiceReviewFieldSourceSwitch({
    super.key,
    required this.selection,
    required this.onSelected,
    this.aiEnabled = true,
    this.localLabel = 'OCR',
    this.aiLabel = 'AI',
  });

  final InvoiceReviewFieldSourceSelection selection;
  final ValueChanged<InvoiceReviewFieldSourceSelection> onSelected;
  final bool aiEnabled;
  final String localLabel;
  final String aiLabel;

  static const double _height = 34;
  static const double _width = 112;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isManual = selection == InvoiceReviewFieldSourceSelection.manual;

    return Semantics(
      label: isManual
          ? '目前使用手動值，可切換 OCR 或 AI'
          : '辨識來源：${selection == InvoiceReviewFieldSourceSelection.local ? localLabel : aiLabel}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_height / 2),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Stack(
              children: <Widget>[
                AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  alignment: selection == InvoiceReviewFieldSourceSelection.ai
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: isManual ? 0 : 1,
                    child: Container(
                      width: (_width - 6) / 2,
                      height: _height - 4,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular((_height - 4) / 2),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            blurRadius: 3,
                            offset: Offset(0, 1),
                            color: Color(0x33000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _SourceButton(
                        key: const Key('invoice_source_switch_local'),
                        icon: Icons.document_scanner_outlined,
                        label: localLabel,
                        enabled: true,
                        selected:
                            selection == InvoiceReviewFieldSourceSelection.local,
                        onTap: () => onSelected(
                          InvoiceReviewFieldSourceSelection.local,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _SourceButton(
                        key: const Key('invoice_source_switch_ai'),
                        icon: Icons.auto_awesome_outlined,
                        label: aiLabel,
                        enabled: aiEnabled,
                        selected:
                            selection == InvoiceReviewFieldSourceSelection.ai,
                        onTap: () => onSelected(
                          InvoiceReviewFieldSourceSelection.ai,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isManual) ...<Widget>[
            const SizedBox(width: 6),
            Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              label: const Text('手動'),
              avatar: const Icon(Icons.edit_outlined, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.32)
        : selected
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: enabled ? onTap : null,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
