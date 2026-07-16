import 'dart:async';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/screens/wall/widgets/post_card.dart';
import 'package:safezone/screens/stats/stats_screen.dart';
import 'package:shimmer/shimmer.dart';

class FeedScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const FeedScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ReportService _reportService = ReportService();
  final SupabaseService _supabase = SupabaseService();
  List<Report> _reports = [];
  bool _isLoading = true;
  String _filterTag = 'todas';
  StreamSubscription<List<Report>>? _reportSubscription;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _subscribeToRealtime();
  }

  void _subscribeToRealtime() {
    try {
      _reportSubscription = _supabase.client
          .from(_supabase.reportsTable)
          .stream(primaryKey: ['id'])
          .eq('zone', widget.zone)
          .order('created_at', ascending: false)
          .limit(50)
          .map((maps) =>
              maps.map((m) => Report.fromMap(m)).toList())
          .listen((reports) {
        if (mounted) {
          setState(() {
            _reports = reports;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      debugPrint('FeedScreen realtime error: $e');
    }
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final reports = await _reportService.getReports(zone: widget.zone);
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

  List<Report> get _filteredReports {
    if (_filterTag == 'todas') return _reports;
    return _reports.where((r) => r.tag == _filterTag).toList();
  }

  @override
  void dispose() {
    _reportSubscription?.cancel();
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
            const Text('SafeZone', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Stats button
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StatsScreen(
                    userCode: widget.userCode,
                    zone: widget.zone,
                  ),
                ),
              );
            },
            tooltip: 'Estadísticas',
          ),
          // Zone badge
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
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FilterChip(
                  label: 'Todas',
                  isSelected: _filterTag == 'todas',
                  onTap: () => setState(() => _filterTag = 'todas'),
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '🔴 Peligro',
                  isSelected: _filterTag == 'rojo',
                  onTap: () => setState(() => _filterTag = 'rojo'),
                  color: AppTheme.dangerRed,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '🟡 Alerta',
                  isSelected: _filterTag == 'amarillo',
                  onTap: () => setState(() => _filterTag = 'amarillo'),
                  color: AppTheme.warningYellow,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '🟢 Seguro',
                  isSelected: _filterTag == 'verde',
                  onTap: () => setState(() => _filterTag = 'verde'),
                  color: AppTheme.safeGreen,
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: _isLoading
            ? _buildShimmer()
            : _filteredReports.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredReports.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${_filteredReports.length} reporte${_filteredReports.length != 1 ? 's' : ''} activo${_filteredReports.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }
                      return PostCard(
                        report: _filteredReports[index - 1],
                        userCode: widget.userCode,
                        onReactionChanged: _loadReports,
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 4,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
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
            'No hay reportes en esta categoría',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Cuando los vecinos reporten, aparecerán aquí',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Colors.white,
          ),
        ),
      ),
    );
  }
}
