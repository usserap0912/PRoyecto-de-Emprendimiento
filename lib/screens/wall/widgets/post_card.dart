import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/widgets/reaction_buttons.dart';
import 'package:safezone/widgets/tag_badge.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostCard extends StatelessWidget {
  final Report report;
  final String userCode;
  final VoidCallback onReactionChanged;

  const PostCard({
    super.key,
    required this.report,
    required this.userCode,
    required this.onReactionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // User avatar placeholder
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                  child: Text(
                    report.userCode.substring(5, 7),
                    style: const TextStyle(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.userCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${timeago.format(report.createdAt, locale: 'es')} · Zona ${report.zone}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TagBadge(tag: report.tag, label: report.tagLabel),
              ],
            ),
          ),
          // Category
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _buildCategoryChip(report.category),
                if (report.status == 'resuelto')
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.safeGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 12, color: AppTheme.safeGreen),
                        SizedBox(width: 4),
                        Text(
                          'Resuelto',
                          style: TextStyle(fontSize: 11, color: AppTheme.safeGreen),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              report.description,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
          // Image if available
          if (report.imageUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 200,
                width: double.infinity,
                color: Colors.grey[200],
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_outlined, size: 40, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Imagen adjunta',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Address if available
          if (report.address != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      report.address!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // Reaction buttons
          ReactionButtons(
            shieldCount: report.shieldCount,
            alertCount: report.alertCount,
            checkCount: report.checkCount,
            onShieldTap: () {
              // Handle shield reaction
              onReactionChanged();
            },
            onAlertTap: () {
              // Handle alert reaction
              onReactionChanged();
            },
            onCheckTap: () {
              // Handle check reaction
              onReactionChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    IconData icon;
    Color color;
    String label;

    switch (category) {
      case 'robo':
        icon = Icons.visibility_off;
        color = AppTheme.dangerRed;
        label = 'Robo';
        break;
      case 'sospechoso':
        icon = Icons.person_search;
        color = AppTheme.warningYellow;
        label = 'Sospechoso';
        break;
      case 'extorsion':
        icon = Icons.block;
        color = AppTheme.dangerRed;
        label = 'Extorsión';
        break;
      case 'alumbrado':
        icon = Icons.lightbulb_outline;
        color = AppTheme.warningYellow;
        label = 'Alumbrado';
        break;
      default:
        icon = Icons.info_outline;
        color = Colors.grey;
        label = 'Otros';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
