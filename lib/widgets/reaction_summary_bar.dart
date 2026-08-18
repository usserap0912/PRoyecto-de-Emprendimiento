import 'package:flutter/material.dart';
import 'package:safezone/models/report_reaction.dart';
import 'package:safezone/theme/app_theme.dart';

class ReactionSummaryBar extends StatelessWidget {
  const ReactionSummaryBar({
    super.key,
    required this.summary,
    required this.onReactionTap,
    required this.onOpenPicker,
  });

  final ReactionSummary summary;
  final ValueChanged<String> onReactionTap;
  final VoidCallback onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final existing = summary.counts.entries
        .where((entry) => entry.value > 0)
        .toList();
    if (existing.isEmpty) {
      return InkWell(
        key: const ValueKey('empty_reaction_hint'),
        onTap: onOpenPicker,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            'Mantén presionado para reaccionar',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in existing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                key: ValueKey('reaction_${entry.key}'),
                onTap: () => onReactionTap(entry.key),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: summary.currentUserEmoji == entry.key
                        ? AppTheme.primaryGreen.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${entry.key} ${entry.value}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: summary.currentUserEmoji == entry.key
                          ? AppTheme.primaryGreen
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('open_emoji_picker'),
            onPressed: onOpenPicker,
            tooltip: 'Agregar o cambiar reacción',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_reaction_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}
