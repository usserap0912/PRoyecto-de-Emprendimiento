import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/app.dart';

class StatsScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const StatsScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          // Dark mode toggle
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              SafeZoneAppState.instance?.toggleTheme();
            },
            tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Avatar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield,
                size: 64,
                color: AppTheme.primaryGreen,
              ),
            ),
            const SizedBox(height: 20),

            // User code
            Text(
              widget.userCode,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Zona ${widget.zone} • Collique',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Identidad anónima',
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),

            const SizedBox(height: 32),

            // Stats cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.newspaper,
                    label: 'Reportes',
                    value: '—',
                    color: AppTheme.primaryGreen,
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.shield,
                    label: 'Reacciones',
                    value: '—',
                    color: AppTheme.shieldBlue,
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.sos,
                    label: 'Alertas SOS',
                    value: '—',
                    color: AppTheme.sosRed,
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu información',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.code,
                    label: 'Código',
                    value: widget.userCode,
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.map,
                    label: 'Zona',
                    value: 'Zona ${widget.zone} - Collique, Comas',
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: isDark ? Icons.light_mode : Icons.dark_mode,
                    label: 'Tema',
                    value: isDark ? 'Oscuro' : 'Claro',
                    textColor: textColor,
                    mutedColor: mutedColor,
                    trailing: Switch(
                      value: isDark,
                      onChanged: (_) {
                        SafeZoneAppState.instance?.toggleTheme();
                      },
                      activeThumbColor: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // About
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SafeZone',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Red vecinal de seguridad de Collique, Comas.\n'
                    'Versión 1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: mutedColor,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color cardColor;
  final Color textColor;
  final Color mutedColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.cardColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: mutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color mutedColor;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.mutedColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: mutedColor),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
