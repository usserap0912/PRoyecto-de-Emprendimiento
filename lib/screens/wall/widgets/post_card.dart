import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/widgets/reaction_buttons.dart';
import 'package:safezone/widgets/tag_badge.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostCard extends StatefulWidget {
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
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  final ReportService _reportService = ReportService();
  Set<String> _userReactions = {};

  // Animación para SOS
  late AnimationController _sosPulseController;

  bool get _isSos => widget.report.category == 'sos';

  @override
  void initState() {
    super.initState();
    _loadUserReactions();
    _sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (_isSos) _sosPulseController.repeat(reverse: true);
  }

  Future<void> _loadUserReactions() async {
    final reactions = await _reportService.getUserReactions(
        widget.report.id, widget.userCode);
    if (mounted) setState(() => _userReactions = reactions);
  }

  Future<void> _handleReaction(String reactionType) async {
    final wasActive = _userReactions.contains(reactionType);
    await _reportService.toggleReaction(
        widget.report.id, widget.userCode, reactionType);
    // Otorgar puntos solo si es una reacción NUEVA (no al quitarla)
    if (!wasActive) {
      SupabaseService().addVecinoPoints(
        userCode: widget.userCode,
        points: 5,
        reason: 'reaction',
        description: 'Reaccionó a un reporte',
      );
    }
    await _loadUserReactions();
    widget.onReactionChanged();
  }

  @override
  void dispose() {
    _sosPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[500]!;

    // Fondo tintado para SOS
    final sosBgColor = _isSos
        ? (isDark
            ? AppTheme.sosRed.withValues(alpha: 0.15)
            : const Color(0xFFFFEBEE))
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: sosBgColor,
      shape: _isSos
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          : null,
      child: _isSos
          ? _buildSosContent(isDark, textColor, mutedColor)
          : _buildNormalContent(isDark, textColor, mutedColor),
    );
  }

  /// Contenido normal (no SOS)
  Widget _buildNormalContent(
      bool isDark, Color textColor, Color mutedColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(isDark, textColor, mutedColor),
        _buildCategory(isDark),
        _buildDescription(isDark, textColor),
        _buildImage(isDark, mutedColor),
        _buildAddress(mutedColor),
        const Divider(height: 1),
        _buildReactions(),
      ],
    );
  }

  /// Contenido SOS con borde pulsante y overlay
  Widget _buildSosContent(bool isDark, Color textColor, Color mutedColor) {
    return AnimatedBuilder(
      animation: _sosPulseController,
      builder: (context, child) {
        final pulse = _sosPulseController.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.sosRed.withValues(alpha: 0.3 + pulse * 0.5),
              width: 2.0 + pulse * 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sosRed.withValues(alpha: 0.15 + pulse * 0.2),
                blurRadius: 8 + pulse * 6,
                spreadRadius: pulse * 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overlay badge SOS
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSosBadge(),
                        _buildHeader(isDark, textColor, mutedColor),
                        _buildCategory(isDark),
                        _buildDescription(isDark, textColor),
                        _buildImage(isDark, mutedColor),
                        _buildAddress(mutedColor),
                        const Divider(height: 1),
                        _buildReactions(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Badge SOS especial con icono pulsante
  Widget _buildSosBadge() {
    return AnimatedBuilder(
      animation: _sosPulseController,
      builder: (context, child) {
        final pulse = _sosPulseController.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.sosRed.withValues(alpha: 0.2 + pulse * 0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.sos,
                size: 16 + pulse * 2,
                color: AppTheme.sosRed,
              ),
              const SizedBox(width: 8),
              Text(
                '🚨 ALERTA S.O.S. ACTIVA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.sosRed,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Indicador pulsante
              Container(
                width: 8 + pulse * 2,
                height: 8 + pulse * 2,
                decoration: BoxDecoration(
                  color: AppTheme.sosRed,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Header con avatar, nombre, tiempo y tag
  Widget _buildHeader(
      bool isDark, Color textColor, Color mutedColor) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, _isSos ? 10 : 14, 16, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _isSos
                ? AppTheme.sosRed.withValues(alpha: 0.15)
                : AppTheme.primaryGreen.withValues(alpha: 0.1),
            child: Text(
              widget.report.userCode.substring(5, 7),
              style: TextStyle(
                color: _isSos ? AppTheme.sosRed : AppTheme.primaryGreen,
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
                  widget.report.userCode,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${timeago.format(widget.report.createdAt, locale: 'es')} · Zona ${widget.report.zone}',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TagBadge(tag: widget.report.tag, label: widget.report.tagLabel),
        ],
      ),
    );
  }

  /// Categoría
  Widget _buildCategory(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _CategoryChip(category: widget.report.category),
          if (widget.report.status == 'resuelto')
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.safeGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 12, color: AppTheme.safeGreen),
                  SizedBox(width: 4),
                  Text(
                    'Resuelto',
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.safeGreen),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Descripción
  Widget _buildDescription(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        widget.report.description,
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: textColor,
          fontWeight: _isSos ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }

  /// Imagen
  Widget _buildImage(bool isDark, Color mutedColor) {
    if (widget.report.imageUrl == null ||
        !widget.report.imageUrl!.startsWith('http')) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () =>
                  _showImageFullscreen(context, widget.report.imageUrl!),
              child: Image.network(
                widget.report.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    color: isDark ? AppTheme.darkSurface : Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: isDark ? AppTheme.darkSurface : Colors.grey[200],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              size: 40, color: mutedColor),
                          const SizedBox(height: 8),
                          Text('No se pudo cargar la imagen',
                              style: TextStyle(
                                  color: mutedColor, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Dirección
  Widget _buildAddress(Color mutedColor) {
    if (widget.report.address == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: mutedColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.report.address!,
              style: TextStyle(fontSize: 12, color: mutedColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Botones de reacción
  Widget _buildReactions() {
    return ReactionButtons(
      shieldCount: widget.report.shieldCount,
      alertCount: widget.report.alertCount,
      checkCount: widget.report.checkCount,
      shieldActive: _userReactions.contains('shield'),
      alertActive: _userReactions.contains('alert'),
      checkActive: _userReactions.contains('check'),
      onShieldTap: () => _handleReaction('shield'),
      onAlertTap: () => _handleReaction('alert'),
      onCheckTap: () => _handleReaction('check'),
    );
  }

  void _showImageFullscreen(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.white));
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image,
                            color: Colors.white54, size: 64),
                        SizedBox(height: 16),
                        Text('Error al cargar imagen',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget extraído para reuso — usa Report.categoryLabelFor y categoryIconFor
class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final color = Report.categoryColorFor(category);
    final icon = Report.categoryIconFor(category);
    final label = Report.categoryLabelFor(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
