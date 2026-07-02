import 'dart:async';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/report_comment.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/widgets/report_video_player.dart';
import 'package:safezone/widgets/tag_badge.dart';
import 'package:timeago/timeago.dart' as timeago;

class WallScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const WallScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends State<WallScreen> {
  final ReportService _reportService = ReportService();
  List<Report> _reports = [];
  bool _isLoading = true;

  // Filtro temporal activo: null = sin filtro
  String? _activeTimeFilter;

  // Opciones de filtro temporal
  static const List<_TimeFilterOption> _timeFilters = [
    _TimeFilterOption(label: 'Últimas horas', value: 'today'),
    _TimeFilterOption(label: 'Hace 1 día', value: '1day'),
    _TimeFilterOption(label: 'Hace 2 días', value: '2days'),
    _TimeFilterOption(label: 'Esta semana', value: 'week'),
  ];

  @override
  void initState() {
    super.initState();
    _loadReports();
    _subscribeToRealtime();
  }

  /// Carga inicial de reportes
  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final reports = await _reportService.getReports(
        zone: widget.zone,
        timeFilter: _activeTimeFilter,
      );
      if (mounted) {
        setState(() {
          _reports = reports;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Suscripción en tiempo real con Supabase Channel
  void _subscribeToRealtime() {
    _reportService.subscribeToRealtime(
      zone: widget.zone,
      onData: (reports) {
        if (mounted) {
          setState(() {
            _reports = reports;
            _isLoading = false;
          });
        }
      },
    );
  }

  /// Cambia el filtro temporal y recarga
  void _setTimeFilter(String? filter) {
    setState(() => _activeTimeFilter = _activeTimeFilter == filter ? null : filter);
    _loadReports();
  }

  @override
  void dispose() {
    _reportService.unsubscribeFromRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, size: 24),
            const SizedBox(width: 8),
            const Text('SafeZone', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            '${_reports.length} reporte${_reports.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }
                      return _ReportCard(
                        report: _reports[index - 1],
                        userCode: widget.userCode,
                        onReactionChanged: _loadReports,
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
            for (final filter in _timeFilters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TimeFilterChip(
                  label: filter.label,
                  isActive: _activeTimeFilter == filter.value,
                  onTap: () => _setTimeFilter(filter.value),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No hay reportes en este período',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Los reportes aparecerán aquí en tiempo real',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MODELO INTERNO: Filtro temporal
// ============================================================

class _TimeFilterOption {
  final String label;
  final String value;
  const _TimeFilterOption({required this.label, required this.value});
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
  final VoidCallback onReactionChanged;

  const _ReportCard({
    required this.report,
    required this.userCode,
    required this.onReactionChanged,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final ReportService _reportService = ReportService();
  Set<String> _userReactions = {};

  @override
  void initState() {
    super.initState();
    _loadUserReactions();
  }

  Future<void> _loadUserReactions() async {
    final reactions = await _reportService.getUserReactions(
        widget.report.id, widget.userCode);
    if (mounted) setState(() => _userReactions = reactions);
  }

  /// Alterna una reacción emoji
  Future<void> _handleEmojiReaction(String reactionType) async {
    await _reportService.toggleEmojiReaction(
        widget.report.id, widget.userCode, reactionType);
    await _loadUserReactions();
    widget.onReactionChanged();
  }

  /// Abre la hoja de comentarios
  void _openCommentsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentsSheet(
        reportId: widget.report.id,
        userCode: widget.userCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[500]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === HEADER: Avatar + usuario + tiempo + tag ===
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
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
                TagBadge(tag: widget.report.tag, label: widget.report.tagLabel),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.safeGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 12, color: AppTheme.safeGreen),
                        SizedBox(width: 4),
                        Text('Resuelto',
                            style: TextStyle(fontSize: 11, color: AppTheme.safeGreen)),
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
                  onTap: () => _showImageFullscreen(context, widget.report.imageUrl!),
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
                              Icon(Icons.broken_image_outlined, size: 40, color: mutedColor),
                              const SizedBox(height: 8),
                              Text('No se pudo cargar la imagen',
                                  style: TextStyle(color: mutedColor, fontSize: 13)),
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

          const SizedBox(height: 8),

          // === DIRECCIÓN ===
          if (widget.report.address != null)
            Padding(
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
            ),

          const Divider(height: 1),

          // === EMOJIS + COMENTARIOS (footer) ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Emoji reactions: 🛡️ ⚠️ 😮 🙏
                _EmojiButton(
                  emoji: '🛡️',
                  label: 'shield',
                  count: widget.report.shieldCount,
                  isActive: _userReactions.contains('shield'),
                  onTap: () => _handleEmojiReaction('shield'),
                ),
                _EmojiButton(
                  emoji: '⚠️',
                  label: 'alert',
                  count: widget.report.alertCount,
                  isActive: _userReactions.contains('alert'),
                  onTap: () => _handleEmojiReaction('alert'),
                ),
                _EmojiButton(
                  emoji: '😮',
                  label: 'surprised',
                  count: 0,
                  isActive: _userReactions.contains('surprised'),
                  onTap: () => _handleEmojiReaction('surprised'),
                ),
                _EmojiButton(
                  emoji: '🙏',
                  label: 'pray',
                  count: widget.report.checkCount,
                  isActive: _userReactions.contains('pray'),
                  onTap: () => _handleEmojiReaction('pray'),
                ),
                const Spacer(),
                // Botón de comentarios
                GestureDetector(
                  onTap: () => _openCommentsSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.shieldBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 16, color: AppTheme.shieldBlue),
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
                      child: CircularProgressIndicator(color: Colors.white));
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white54, size: 64),
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

// ============================================================
// BOTÓN DE EMOJI REACTION
// ============================================================

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: TextStyle(fontSize: isActive ? 17 : 15)),
              const SizedBox(width: 3),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppTheme.primaryGreen : Colors.grey[600],
                ),
              ),
            ],
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

  const _CommentsSheet({
    required this.reportId,
    required this.userCode,
  });

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

  @override
  void initState() {
    super.initState();
    _subscribeToComments();
  }

  void _subscribeToComments() {
    _commentsSubscription =
        _reportService.getCommentsStream(widget.reportId).listen((comments) {
      if (mounted) setState(() => _comments = comments);
    });
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final success = await _reportService.addComment(
      reportId: widget.reportId,
      userCode: widget.userCode,
      content: text,
    );
    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        _textController.clear();
        _focusNode.unfocus();
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

            // === Lista de comentarios ===
            Expanded(
              child: _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'Sin comentarios aún',
                            style: TextStyle(color: Colors.grey[500], fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sé el primero en comentar',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
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
                                    ? AppTheme.primaryGreen.withValues(alpha: 0.15)
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
                                          timeago.format(comment.createdAt,
                                              locale: 'es'),
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
                                            ? AppTheme.primaryGreen.withValues(alpha: 0.06)
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
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.95),
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
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        filled: true,
                        fillColor: isDark ? AppTheme.darkSurface : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
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
