import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';

class ReportFormScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const ReportFormScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _descriptionController = TextEditingController();
  final SupabaseService _supabase = SupabaseService();
  final ImagePicker _picker = ImagePicker();

  String? _selectedCategory;
  String? _selectedTag;
  String? _riskLevel;       // <-- NUEVO: 'baja', 'media', 'alta', 'critica'
  String? _imagePath;
  String? _videoPath;
  bool _isSubmitting = false;
  bool _showSuccess = false;
  bool _bucketReady = false;
  double? _currentLat;
  double? _currentLng;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _checkStorageBucket();
  }

  Future<void> _checkStorageBucket() async {
    final ready = await _supabase.ensureStorageBucket();
    if (mounted) setState(() => _bucketReady = ready);
  }

  // ================================================================
  // DATOS ESTÁTICOS
  // ================================================================
  final List<Map<String, dynamic>> _categories = [
    {'key': 'robo', 'label': 'Robo', 'icon': Icons.visibility_off, 'color': AppTheme.dangerRed},
    {'key': 'sospechoso', 'label': 'Sospechoso', 'icon': Icons.person_search, 'color': AppTheme.warningYellow},
    {'key': 'extorsion', 'label': 'Extorsión', 'icon': Icons.block, 'color': AppTheme.dangerRed},
    {'key': 'alumbrado', 'label': 'Alumbrado', 'icon': Icons.lightbulb_outline, 'color': AppTheme.warningYellow},
    {'key': 'otros', 'label': 'Otros', 'icon': Icons.info_outline, 'color': Colors.grey},
  ];

  final List<Map<String, dynamic>> _tags = [
    {'key': 'rojo', 'label': '🔴 Peligro Grave', 'desc': 'Robo, extorsión, peligro inminente'},
    {'key': 'amarillo', 'label': '🟡 Alerta Preventiva', 'desc': 'Sospechosos, precaución'},
    {'key': 'verde', 'label': '🟢 Buena Noticia', 'desc': 'Zona segura, serenazgo presente'},
  ];

  /// Opciones para el Dropdown de Nivel de Riesgo
  final List<Map<String, dynamic>> _riskLevels = [
    {'value': 'baja', 'label': '🟢 Baja', 'color': AppTheme.safeGreen},
    {'value': 'media', 'label': '🟡 Media', 'color': AppTheme.warningYellow},
    {'value': 'alta', 'label': '🟠 Alta', 'color': AppTheme.alertOrange},
    {'value': 'critica', 'label': '🔴 Crítica', 'color': AppTheme.dangerRed},
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // ================================================================
  // CÁMARA / GALERÍA (sin cambios)
  // ================================================================
  Future<void> _pickImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null && mounted) setState(() => _imagePath = photo.path);
    } catch (e) {
      if (!mounted) return;
      final XFile? gallery = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (gallery != null && mounted) setState(() => _imagePath = gallery.path);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null && mounted) setState(() => _videoPath = video.path);
    } catch (e) {
      // Fallback
    }
  }

  // ================================================================
  // GEOLOCALIZACIÓN
  // ================================================================
  Future<bool> _obtenerUbicacion() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activa el GPS para reportar tu ubicación'),
              backgroundColor: AppTheme.warningYellow,
            ),
          );
        }
        setState(() => _isLocating = false);
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Necesitamos permisos de ubicación para reportar'),
                backgroundColor: AppTheme.warningYellow,
              ),
            );
          }
          setState(() => _isLocating = false);
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permisos de ubicación denegados permanentemente. Ve a Configuración > SafeZone > Ubicación'),
              backgroundColor: AppTheme.dangerRed,
              duration: Duration(seconds: 4),
            ),
          );
        }
        setState(() => _isLocating = false);
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _isLocating = false;
        });
      }
      return true;
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      if (mounted) setState(() => _isLocating = false);
      return false;
    }
  }

  // ================================================================
  // FUNCIÓN MATEMÁTICA: DETERMINAR ZONA COLLIQUE (Haversine simplificado)
  // ================================================================
  int _determinarZonaCollique(double lat, double lng) {
    final Map<int, Map<String, double>> zonasCollique = {
      1:  {'lat': -11.9447, 'lng': -77.0611},
      2:  {'lat': -11.9412, 'lng': -77.0575},
      3:  {'lat': -11.9378, 'lng': -77.0540},
      4:  {'lat': -11.9345, 'lng': -77.0505},
      5:  {'lat': -11.9310, 'lng': -77.0465},
      6:  {'lat': -11.9275, 'lng': -77.0425},
      7:  {'lat': -11.9240, 'lng': -77.0385},
      8:  {'lat': -11.9205, 'lng': -77.0345},
      9:  {'lat': -11.9360, 'lng': -77.0490},
      10: {'lat': -11.9290, 'lng': -77.0390},
      11: {'lat': -11.9220, 'lng': -77.0290},
      12: {'lat': -11.9180, 'lng': -77.0250},
      13: {'lat': -11.9400, 'lng': -77.0450},
      14: {'lat': -11.9435, 'lng': -77.0530},
    };

    int zonaMasCercana = 1;
    double distanciaMinima = double.infinity;

    zonasCollique.forEach((zona, coords) {
      final double dLat = lat - coords['lat']!;
      final double dLng = lng - coords['lng']!;
      final double distancia = (dLat * dLat) + (dLng * dLng);

      if (distancia < distanciaMinima) {
        distanciaMinima = distancia;
        zonaMasCercana = zona;
      }
    });

    return zonaMasCercana;
  }

  // ================================================================
  // ENVÍO DEL REPORTE
  // ================================================================
  Future<void> _submitReport() async {
    // Validaciones
    if (_selectedCategory == null ||
        _descriptionController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una categoría y escribe una descripción'),
          backgroundColor: AppTheme.warningYellow,
        ),
      );
      return;
    }

    if (_riskLevel == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona el nivel de riesgo'),
          backgroundColor: AppTheme.warningYellow,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    // Obtener ubicación
    final ubicacionOk = await _obtenerUbicacion();
    if (!ubicacionOk) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    try {
      // Leer user_code desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userCode = prefs.getString('user_device_code') ?? widget.userCode;

      // Determinar zona usando Haversine
      final zonaDeterminada = _determinarZonaCollique(_currentLat!, _currentLng!);

      // Construir payload para Supabase
      final reportData = <String, dynamic>{
        'user_code': userCode,
        'lat': _currentLat,
        'lng': _currentLng,
        'category': _selectedCategory,
        'risk_level': _riskLevel,
        'description': _descriptionController.text.trim(),
        'zone_number': zonaDeterminada,
        'tag': _selectedTag ?? 'amarillo',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Subir imagen si existe
      if (_imagePath != null) {
        final imageUrl = await _supabase.uploadFile(_imagePath!);
        if (imageUrl != null) reportData['media_url'] = imageUrl;
      }

      // Subir video si existe
      if (_videoPath != null) {
        final videoUrl = await _supabase.uploadFile(_videoPath!, isVideo: true);
        if (videoUrl != null) reportData['video_url'] = videoUrl;
      }

      // Insertar en Supabase tabla 'reports'
      await _supabase.client.from('reports').insert(reportData);

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _showSuccess = true;
          _selectedCategory = null;
          _selectedTag = null;
          _riskLevel = null;
          _imagePath = null;
          _videoPath = null;
          _descriptionController.clear();
          _currentLat = null;
          _currentLng = null;
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showSuccess = false);
        });
      }
    } catch (e) {
      debugPrint('Error al enviar reporte: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar el reporte. Intenta de nuevo.'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Incidente'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.brandRedDark, AppTheme.brandRedBright],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (_showSuccess)
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent),
                  SizedBox(width: 4),
                  Text('¡Enviado!', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
      body: _showSuccess ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.safeGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline, size: 80, color: AppTheme.safeGreen),
          ),
          const SizedBox(height: 24),
          const Text('¡Reporte Enviado!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Tu reporte ya está visible en el Muro\ny en el Mapa de Riesgo de Collique',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () { if (mounted) setState(() => _showSuccess = false); },
            child: const Text('REPORTAR OTRO INCIDENTE'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==========================================
          // 1. CATEGORÍA
          // ==========================================
          const Text('¿Qué está pasando?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat['key'];
              return Expanded(
                child: GestureDetector(
                  onTap: () { if (mounted) setState(() => _selectedCategory = cat['key'] as String); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? (cat['color'] as Color).withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? cat['color'] as Color : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(cat['icon'] as IconData, color: isSelected ? cat['color'] as Color : Colors.grey[400], size: 24),
                        const SizedBox(height: 4),
                        Text(
                          cat['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? cat['color'] as Color : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // ==========================================
          // 2. NIVEL DE RIESGO (NUEVO)
          // ==========================================
          const Text('Nivel de Riesgo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _riskLevel,
            decoration: InputDecoration(
              hintText: 'Selecciona el nivel de riesgo',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: _riskLevels.map((rl) {
              return DropdownMenuItem<String>(
                value: rl['value'] as String,
                child: Row(
                  children: [
                    Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: rl['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(rl['label'] as String, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) { if (mounted) setState(() => _riskLevel = value); },
          ),

          const SizedBox(height: 24),

          // ==========================================
          // 3. NIVEL DE GRAVEDAD (TAG)
          // ==========================================
          const Text('Nivel de gravedad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ..._tags.map((tag) {
            final isSelected = _selectedTag == tag['key'];
            return GestureDetector(
              onTap: () { if (mounted) setState(() => _selectedTag = tag['key'] as String); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryGreen : Colors.grey[200]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? AppTheme.primaryGreen : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tag['label'] as String, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: isSelected ? Colors.black87 : Colors.grey[600])),
                        Text(tag['desc'] as String, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          // ==========================================
          // 4. DESCRIPCIÓN
          // ==========================================
          const Text('Describe lo que viste', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Ej: Vi una moto sospechosa dando vueltas en la Av. Revolución...',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),

          const SizedBox(height: 16),

          // ==========================================
          // 5. SUBIR EVIDENCIA
          // ==========================================
          const Text('Sube evidencia (opcional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (!_bucketReady)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, size: 18, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las fotos se guardarán localmente. Crea el bucket "safezone-images" en Supabase para subirlas a la nube.',
                      style: TextStyle(fontSize: 11, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: _imagePath != null ? AppTheme.primaryGreen.withValues(alpha: 0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _imagePath != null ? AppTheme.primaryGreen : Colors.grey[300]!,
                        width: _imagePath != null ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_imagePath != null ? Icons.check_circle : Icons.camera_alt_outlined,
                            color: _imagePath != null ? AppTheme.primaryGreen : Colors.grey[400], size: 28),
                        const SizedBox(height: 4),
                        Text(_imagePath != null ? 'Foto lista' : 'Tomar Foto',
                            style: TextStyle(fontSize: 12, color: _imagePath != null ? AppTheme.primaryGreen : Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _pickVideo,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: _videoPath != null ? AppTheme.primaryGreen.withValues(alpha: 0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _videoPath != null ? AppTheme.primaryGreen : Colors.grey[300]!,
                        width: _videoPath != null ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_videoPath != null ? Icons.check_circle : Icons.videocam_outlined,
                            color: _videoPath != null ? AppTheme.primaryGreen : Colors.grey[400], size: 28),
                        const SizedBox(height: 4),
                        Text(_videoPath != null ? 'Video listo' : 'Grabar Video',
                            style: TextStyle(fontSize: 12, color: _videoPath != null ? AppTheme.primaryGreen : Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ==========================================
          // INDICADOR DE UBICACIÓN
          // ==========================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _currentLat != null
                  ? AppTheme.safeGreen.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _currentLat != null
                    ? AppTheme.safeGreen.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isLocating
                      ? Icons.gps_fixed
                      : _currentLat != null
                          ? Icons.location_on
                          : Icons.location_searching,
                  size: 18,
                  color: _isLocating
                      ? AppTheme.warningYellow
                      : _currentLat != null
                          ? AppTheme.safeGreen
                          : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isLocating
                        ? 'Obteniendo ubicación...'
                        : _currentLat != null
                            ? '📍 Ubicación capturada (${_currentLat!.toStringAsFixed(4)}, ${_currentLng!.toStringAsFixed(4)})'
                            : 'La ubicación se capturará al enviar',
                    style: TextStyle(
                      fontSize: 12,
                      color: _currentLat != null ? AppTheme.safeGreen : Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ==========================================
          // BOTÓN ENVIAR
          // ==========================================
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSubmitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isLocating ? 'Obteniendo ubicación...' : 'Enviando...',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('ENVIAR REPORTE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Tu identidad permanecerá anónima', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
