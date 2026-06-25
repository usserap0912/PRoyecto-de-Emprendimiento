import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

class ReactionButtons extends StatefulWidget {
  final int shieldCount;
  final int alertCount;
  final int checkCount;
  final bool shieldActive;
  final bool alertActive;
  final bool checkActive;
  final VoidCallback onShieldTap;
  final VoidCallback onAlertTap;
  final VoidCallback onCheckTap;

  const ReactionButtons({
    super.key,
    required this.shieldCount,
    required this.alertCount,
    required this.checkCount,
    this.shieldActive = false,
    this.alertActive = false,
    this.checkActive = false,
    required this.onShieldTap,
    required this.onAlertTap,
    required this.onCheckTap,
  });

  @override
  State<ReactionButtons> createState() => _ReactionButtonsState();
}

class _ReactionButtonsState extends State<ReactionButtons> {
  late bool _shieldActive;
  late bool _alertActive;
  late bool _checkActive;

  @override
  void initState() {
    super.initState();
    _shieldActive = widget.shieldActive;
    _alertActive = widget.alertActive;
    _checkActive = widget.checkActive;
  }

  @override
  void didUpdateWidget(ReactionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizar si el widget padre actualiza los counts
    if (oldWidget.shieldCount != widget.shieldCount ||
        oldWidget.alertCount != widget.alertCount ||
        oldWidget.checkCount != widget.checkCount) {
      // No reseteamos el estado activo del usuario cuando cambian los counts
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ReactionButton(
            icon: Icons.shield_outlined,
            activeIcon: Icons.shield,
            label: 'Escudo',
            count: widget.shieldCount,
            color: AppTheme.shieldBlue,
            isActive: _shieldActive,
            onTap: () {
              setState(() => _shieldActive = !_shieldActive);
              widget.onShieldTap();
            },
          ),
          _ReactionButton(
            icon: Icons.warning_amber_outlined,
            activeIcon: Icons.warning_amber_rounded,
            label: 'Alerta',
            count: widget.alertCount,
            color: AppTheme.alertOrange,
            isActive: _alertActive,
            onTap: () {
              setState(() => _alertActive = !_alertActive);
              widget.onAlertTap();
            },
          ),
          _ReactionButton(
            icon: Icons.check_circle_outline,
            activeIcon: Icons.check_circle,
            label: 'Resuelto',
            count: widget.checkCount,
            color: AppTheme.checkGreen,
            isActive: _checkActive,
            onTap: () {
              setState(() => _checkActive = !_checkActive);
              widget.onCheckTap();
            },
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int count;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.count,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: isActive ? color : Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? color : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? color : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
