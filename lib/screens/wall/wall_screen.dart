import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/report_comment.dart';
import 'package:safezone/models/report_reaction.dart';
import 'package:safezone/models/wall_time_filter.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/widgets/emoji_reaction_picker.dart';
import 'package:safezone/widgets/reaction_summary_bar.dart';
import 'package:safezone/widgets/report_video_player.dart';
import 'package:safezone/widgets/tag_badge.dart';
import 'package:safezone/widgets/reaction_particles.dart';
import 'package:timeago/timeago.dart' as timeago;

class WallScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const WallScreen({super.key, required this.userCode, required this.zone});

  @override
  State<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends State<WallScreen> {
  final ReportService _reportService = ReportService();
  List<Report> _reports = [];
  bool _isLoading = true;
  int _previousReportCount = 0;
  StreamSubscription<Report>? _createdReportSubscription;
  WallTimeFilter _activeTimeFilter = WallTimeFilter.last6Hours;
  Object? _loadError;
  int _loadGeneration = 0;
  Timer? _expirationTimer;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _subscribeToRealtime();
    _createdReportSubscription = _reportService.createdReports.listen(
      _onReportCreated,
    );
  }

  /// Carga inicial de reportes
  Future<void> _loadReports() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final reports = await _reportService.getReports(
        zone: widget.zone,
        timeFilter: _activeTimeFilter,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _reports = reports;
          _previousReportCount = reports.length;
          _isLoading = false;
        });
        _scheduleNextExpiration();
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      }
    }
  }

  /// Suscripción en tiempo real con Supabase Channel
  /// Reproduce sonido cuando llega un nuevo reporte
  void _subscribeToRealtime() {
    _reportService.subscribeToRealtime(
      zone: widget.zone,
      timeFilter: _activeTimeFilter,
      onData: (reports) {
        if (mounted) {
          setState(() {
            final newCount = reports.length;
            // Sonido de nuevo reporte (solo si ya había cargado antes)
            if (_previousReportCount > 0 && newCount > _previousReportCount) {
              SoundService().play('zonebot_open');
              HapticFeedback.mediumImpact();
            }
            _previousReportCount = newCount;
            _reports = reports;
            _isLoading = false;
          });
          _scheduleNextExpiration();
        }
      },
      onError: (error) {
        if (mounted && _reports.isEmpty) setState(() => _loadError = error);
      },
    );
  }

  void _onReportCreated(Report report) {
    if (!mounted || report.zone != widget.zone) return;
    if (!_activeTimeFilter.includes(report.createdAt)) return;
    if (_reports.any((existing) => existing.id == report.id)) return;
    setState(() {
      _reports = _activeTimeFilter.filterAndSort([report, ..._reports]);
      _previousReportCount = _reports.length;
      _isLoading = false;
    });
    _scheduleNextExpiration();
  }

  /// Cambia el filtro temporal y recarga
  void _setTimeFilter(WallTimeFilter filter) {
    if (_activeTimeFilter == filter) return;
    setState(() => _activeTimeFilter = filter);
    _reportService.resubscribe(
      zone: widget.zone,
      timeFilter: filter,
      onData: (reports) {
        if (!mounted) return;
        setState(() {
          _reports = reports;
          _previousReportCount = reports.length;
          _isLoading = false;
          _loadError = null;
        });
        _scheduleNextExpiration();
      },
      onError: (error) {
        if (mounted && _reports.isEmpty) setState(() => _loadError = error);
      },
    );
    _loadReports();
  }

  void _scheduleNextExpiration() {
    _expirationTimer?.cancel();
    if (_reports.isEmpty) return;
    var delay = _activeTimeFilter.nextExpirationDelay(_reports);
    if (delay == null) return;
    if (delay < const Duration(milliseconds: 100)) {
      delay = const Duration(milliseconds: 100);
    } else if (delay > _activeTimeFilter.duration) {
      delay = _activeTimeFilter.duration;
    }
    _expirationTimer = Timer(delay, () {
      if (!mounted) return;
      final visible = _activeTimeFilter.filterAndSort(_reports);
      setState(() {
        _reports = visible;
        _previousReportCount = visible.length;
      });
      _scheduleNextExpiration();
    });
  }

  @override
  void dispose() {
    _createdReportSubscription?.cancel();
    _expirationTimer?.cancel();
    _reportService.unsubscribeFromRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.sectionMuro,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, size: 24),
            const SizedBox(width: 8),
            const Text(
              'SafeZone',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  'Zona ${widget.zone}',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildTimeFilterBar(),
        ),
      ),
      body: _isLoading
          ? _buildShimmer()
          : _loadError != null && _reports.isEmpty
          ? _buildLoadError()
          : _reports.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _reports.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        wallResultLabel(_reports.length),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return _ReportCard(
                    key: ValueKey(_reports[index - 1].id),
                    report: _reports[index - 1],
                    userCode: widget.userCode,
                  );
                },
              ),
            ),
    );
  }

  /// Barra de filtros temporales
  Widget _buildTimeFilterBar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final filter in WallTimeFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TimeFilterChip(
                  label: filter.label,
                  isActive: _activeTimeFilter == filter,
                  onTap: () => _setTimeFilter(filter),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 4,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const WallEmptyState();
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No pudimos cargar el Muro.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _loadReports,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class WallEmptyState extends StatelessWidget {
  const WallEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No hay alertas en este periodo.',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Las publicaciones aparecerán aquí en tiempo real.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHIP DE FILTRO TEMPORAL
// ============================================================

class _TimeFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TimeFilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primaryGreen.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppTheme.primaryGreen
                : Colors.white.withValues(alpha: 0.3),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppTheme.primaryGreen : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TARJETA DE REPORTE
// ============================================================

class _ReportCard extends StatefulWidget {
  final Report report;
  final String userCode;

  const _ReportCard({super.key, required this.report, required this.userCode});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final ReportService _reportService = ReportService();
  StreamSubscription<ReactionSummary>? _reactionSubscription;
  ReactionSummary _reactionSummary = ReactionSummary.empty;
  bool get _isSos => widget.report.category == 'sos';

  @override
  void initState() {
    super.initState();
    _subscribeToReactions();
  }

  @override
  void didUpdateWidget(covariant _ReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id ||
        oldWidget.userCode != widget.userCode) {
      _subscribeToReactions();
    }
  }

  void _subscribeToReactions() {
    unawaited(_reactionSubscription?.cancel());
    _reactionSubscription = _reportService
        .watchReactionSummary(
          widget.report.id,
          currentUserCode: widget.userCode,
        )
        .listen(
          (summary) {
            if (mounted) setState(() => _reactionSummary = summary);
          },
          onError: (Object error) {
            debugPrint('WallScreen reaction realtime error: $error');
          },
        );
  }

  Future<void> _handleEmojiReaction(String emoji) async {
    HapticFeedback.lightImpact();
    unawaited(SoundService().play('button_click'));
    final result = await _reportService.toggleEmojiReaction(
      widget.report.id,
      widget.userCode,
      emoji,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message!)));
      return;
    }
    if (result.action == ReactionMutationAction.set) {
      _showReactionParticles();
    }
  }

  Future<void> _openEmojiPicker() async {
    final emoji = await EmojiReactionPicker.show(
      context,
      currentEmoji: _reactionSummary.currentUserEmoji,
    );
    if (emoji != null && mounted) await _handleEmojiReaction(emoji);
  }

  void _showReactionParticles() {
    try {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final position = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height - 30),
      );
      showReactionParticles(context, position);
    } catch (_) {
      // El efecto es decorativo y nunca debe bloquear la reacción confirmada.
    }
  }

  /// Abre la hoja de comentarios
  void _openCommentsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _CommentsSheet(reportId: widget.report.id, userCode: widget.userCode),
    );
  }

  @override
  void dispose() {
    _reactionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[500]!;

    return GestureDetector(
      onLongPress: () => unawaited(_openEmojiPicker()),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: _isSos
            ? AppTheme.sosRed.withValues(alpha: isDark ? 0.2 : 0.08)
            : null,
        shape: _isSos
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.sosRed, width: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSos)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.sosRed,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sos, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      widget.report.status == 'activo'
                          ? 'ALERTA S.O.S. ACTIVA'
                          : 'ALERTA S.O.S. FINALIZADA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            // === HEADER: Avatar + usuario + tiempo + tag ===
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryGreen.withValues(
                      alpha: 0.1,
                    ),
                    child: Text(
                      widget.report.userCode.length > 7
                          ? widget.report.userCode.substring(5, 7)
                          : '??',
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
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TagBadge(
                    tag: widget.report.tag,
                    label: widget.report.tagLabel,
                  ),
                ],
              ),
            ),

            // === CATEGORÍA ===
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _CategoryChip(category: widget.report.category),
                  if (widget.report.status == 'resuelto')
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.safeGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check,
                            size: 12,
                            color: AppTheme.safeGreen,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Resuelto',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.safeGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // === DESCRIPCIÓN ===
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.report.description,
                style: TextStyle(fontSize: 14, height: 1.4, color: textColor),
              ),
            ),

            // === VIDEO (si existe) ===
            if (widget.report.videoUrl != null &&
                widget.report.videoUrl!.startsWith('http')) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ReportVideoPlayer(videoUrl: widget.report.videoUrl!),
              ),
            ],

            // === IMAGEN (si existe, sin video) ===
            if (widget.report.imageUrl != null &&
                widget.report.imageUrl!.startsWith('http') &&
                (widget.report.videoUrl == null ||
                    !widget.report.videoUrl!.startsWith('http'))) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () =>
                        _showImageFullscreen(context, widget.report.imageUrl!),
                    child: Hero(
                      tag: 'report_img_${widget.report.id}',
                      child: Image.network(
                        widget.report.imageUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: isDark
                                ? AppTheme.darkSurface
                                : Colors.grey[200],
                            child: Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
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
                            color: isDark
                                ? AppTheme.darkSurface
                                : Colors.grey[200],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image_outlined,
                                    size: 40,
                                    color: mutedColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No se pudo cargar la imagen',
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // === DIRECCIÓN ===
            if (widget.report.address != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: mutedColor,
                    ),
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
              ),

            const Divider(height: 1),

            // === EMOJIS + COMENTARIOS (footer) ===
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ReactionSummaryBar(
                      summary: _reactionSummary,
                      onReactionTap: (emoji) =>
                          unawaited(_handleEmojiReaction(emoji)),
                      onOpenPicker: () => unawaited(_openEmojiPicker()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Botón de comentarios
                  GestureDetector(
                    onTap: () => _openCommentsSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.shieldBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 16,
                            color: AppTheme.shieldBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Comentar',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.shieldBlue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageFullscreen(BuildContext context, String imageUrl) {
    // Extraer el ID único de la imagen desde la URL para el Hero
    // Usamos el report id como tag (ya que el widget padre tiene acceso)
    final tag = 'report_img_${widget.report.id}';

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
              child: Hero(
                tag: tag,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Error al cargar imagen',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOJA INFERIOR DE COMENTARIOS
// ============================================================

class _CommentsSheet extends StatefulWidget {
  final String reportId;
  final String userCode;

  const _CommentsSheet({required this.reportId, required this.userCode});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final ReportService _reportService = ReportService();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<List<ReportComment>>? _commentsSubscription;
  List<ReportComment> _comments = [];
  bool _isSending = false;
  String? _streamError;

  @override
  void initState() {
    super.initState();
    _subscribeToComments();
  }

  void _subscribeToComments() {
    _commentsSubscription = _reportService
        .getCommentsStream(widget.reportId)
        .listen(
          (comments) {
            if (mounted) {
              setState(() {
                _comments = comments;
                _streamError = null;
              });
            }
          },
          onError: (Object error) {
            debugPrint('WallScreen comments realtime error: $error');
            if (mounted) {
              setState(() {
                _streamError =
                    'No pudimos actualizar los comentarios en tiempo real.';
              });
            }
          },
        );
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final result = await _reportService.addComment(
      reportId: widget.reportId,
      userCode: widget.userCode,
      content: text,
    );
    if (mounted) {
      if (result.isSuccess) {
        final comment = result.comment!;
        setState(() {
          _isSending = false;
          if (!_comments.any((existing) => existing.id == comment.id)) {
            _comments = [..._comments, comment]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
        });
        _textController.clear();
        _focusNode.unfocus();
      } else {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    }
  }

  @override
  void dispose() {
    _commentsSubscription?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            // === Handle ===
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // === Título ===
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Comentarios',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_comments.length}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            if (_streamError != null)
              MaterialBanner(
                content: Text(_streamError!),
                actions: [
                  TextButton(
                    onPressed: () {
                      _commentsSubscription?.cancel();
                      _subscribeToComments();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),

            // === Lista de comentarios ===
            Expanded(
              child: _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sin comentarios aún',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sé el primero en comentar',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final isMine = comment.userCode == widget.userCode;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isMine
                                    ? AppTheme.primaryGreen.withValues(
                                        alpha: 0.15,
                                      )
                                    : Colors.grey.withValues(alpha: 0.15),
                                child: Text(
                                  comment.userCode.length > 7
                                      ? comment.userCode.substring(5, 7)
                                      : '??',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isMine
                                        ? AppTheme.primaryGreen
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          comment.userCode,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          timeago.format(
                                            comment.createdAt,
                                            locale: 'es',
                                          ),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? AppTheme.primaryGreen.withValues(
                                                alpha: 0.06,
                                              )
                                            : (isDark
                                                  ? AppTheme.darkSurface
                                                  : Colors.grey[100]),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        comment.content,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // === Input de comentario ===
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(
                  alpha: 0.95,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Escribe un comentario...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppTheme.darkSurface
                            : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _sendComment,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isSending
                            ? Colors.grey[300]
                            : AppTheme.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CATEGORY CHIP
// ============================================================

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
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
