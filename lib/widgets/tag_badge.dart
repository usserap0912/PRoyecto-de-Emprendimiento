import 'package:flutter/material.dart';

class TagBadge extends StatelessWidget {
  final String tag;
  final String label;

  const TagBadge({
    super.key,
    required this.tag,
    required this.label,
  });

  Color get _color {
    switch (tag) {
      case 'rojo':
        return const Color(0xFFD32F2F);
      case 'amarillo':
        return const Color(0xFFFFA000);
      case 'verde':
        return const Color(0xFF388E3C);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
