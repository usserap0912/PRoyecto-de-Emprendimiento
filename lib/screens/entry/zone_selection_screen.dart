import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/captcha_screen.dart';

class ZoneSelectionScreen extends StatefulWidget {
  const ZoneSelectionScreen({super.key});

  @override
  State<ZoneSelectionScreen> createState() => _ZoneSelectionScreenState();
}

class _ZoneSelectionScreenState extends State<ZoneSelectionScreen> {
  int? _selectedZone;

  final List<Map<String, dynamic>> _zones = [
    {'number': 1, 'label': '1era Zona', 'icon': Icons.location_city},
    {'number': 2, 'label': '2da Zona', 'icon': Icons.store},
    {'number': 3, 'label': '3ra Zona', 'icon': Icons.park},
    {'number': 4, 'label': '4ta Zona', 'icon': Icons.home},
    {'number': 5, 'label': '5ta Zona', 'icon': Icons.route},
    {'number': 6, 'label': '6ta Zona', 'icon': Icons.apartment},
    {'number': 7, 'label': '7ma Zona', 'icon': Icons.landscape},
    {'number': 8, 'label': '8va Zona', 'icon': Icons.location_on},
    {'number': 9, 'label': '9na Zona', 'icon': Icons.layers},
    {'number': 10, 'label': '10ma Zona', 'icon': Icons.map},
    {'number': 11, 'label': '11va Zona', 'icon': Icons.terrain},
    {'number': 12, 'label': '12va Zona', 'icon': Icons.explore},
    {'number': 13, 'label': '13va Zona', 'icon': Icons.near_me},
    {'number': 14, 'label': '14va Zona / Sector 14', 'icon': Icons.flag},
  ];

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
                    'Escoge tu sector en Collique',
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
                'Elige la zona donde vives para recibir alertas de tu sector',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _zones.length,
                  itemBuilder: (context, index) {
                    final zone = _zones[index];
                    final zoneNum = zone['number'] as int;
                    final isSelected = _selectedZone == zoneNum;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedZone = zoneNum),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryGreen.withValues(alpha: 0.1)
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
                                  ? AppTheme.primaryGreen.withValues(alpha: 0.2)
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
                              zone['icon'] as IconData,
                              size: 28,
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.grey[400],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              zone['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? AppTheme.primaryGreen
                                    : Colors.grey[700],
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
