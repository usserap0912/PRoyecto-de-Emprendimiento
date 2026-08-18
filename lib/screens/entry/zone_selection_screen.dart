import 'package:flutter/material.dart';
import 'package:safezone/models/territorial_zone.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/captcha_screen.dart';
import 'package:safezone/services/territory_service.dart';

typedef TerritorialZonesLoader = Future<List<TerritorialZone>> Function();

class ZoneSelectionScreen extends StatefulWidget {
  const ZoneSelectionScreen({super.key, this.loadZones});

  final TerritorialZonesLoader? loadZones;

  @override
  State<ZoneSelectionScreen> createState() => _ZoneSelectionScreenState();
}

class _ZoneSelectionScreenState extends State<ZoneSelectionScreen> {
  final TerritoryService _territoryService = TerritoryService();
  int? _selectedZone;
  List<TerritorialZone> _zones = const [];
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      final zones =
          await (widget.loadZones?.call() ??
              _territoryService.loadSelectableZones());
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header con logo oficial
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryGreen, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  // Logo oficial de la app
                  Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Image.asset(
                      'assets/icons/logo-app.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.shield,
                          size: 40,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'SafeZone',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escoge tu zona en Collique',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Elige la zona de Collique con la que te identificas para '
                'recibir alertas de tu comunidad',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No se pudieron cargar las zonas verificadas.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () {
                                setState(() {
                                  _loadError = null;
                                  _isLoading = true;
                                });
                                _loadZones();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: _zones.length,
                        itemBuilder: (context, index) {
                          final zone = _zones[index];
                          final zoneNum = zone.zoneNumber;
                          final isSelected = _selectedZone == zoneNum;

                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedZone = zoneNum),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryGreen.withValues(
                                        alpha: 0.1,
                                      )
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primaryGreen
                                      : Colors.grey.shade200,
                                  width: isSelected ? 2.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? AppTheme.primaryGreen.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    zone.referencePoint == null
                                        ? Icons.location_off_outlined
                                        : Icons.location_on_outlined,
                                    size: 28,
                                    color: isSelected
                                        ? AppTheme.primaryGreen
                                        : Colors.grey[400],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    zone.displayLabel,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppTheme.primaryGreen
                                          : Colors.grey[700],
                                    ),
                                  ),
                                  if (zone.referencePoint == null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Sin punto verificado',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isSelected
                                            ? AppTheme.primaryGreen
                                            : Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _selectedZone == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CaptchaScreen(zone: _selectedZone!),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'CONTINUAR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
