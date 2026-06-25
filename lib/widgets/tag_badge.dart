import 'package:flutter/material.dart';
import 'package:safezone/models/report.dart';

class TagBadge extends StatelessWidget {
  final String tag;
  final String label;

  const TagBadge({
    super.key,
    required this.tag,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = Report.tagColorFor(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
