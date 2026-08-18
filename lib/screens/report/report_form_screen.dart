import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:safezone/models/report_form_config.dart';
import 'package:safezone/models/report_submission.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/permission_service.dart';

class ReportFormScreen extends StatefulWidget {
  final String userCode;
  final int zone;
  final ReportService? reportService;
  final Future<ReportCoordinates?> Function()? locationResolver;
  final Future<bool> Function()? storageReadyResolver;

  const ReportFormScreen({
    super.key,
    required this.userCode,
    required this.zone,
    this.reportService,
    this.locationResolver,
    this.storageReadyResolver,
  });

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _descriptionController = TextEditingController();
  final SupabaseService _supabase = SupabaseService();
  final ImagePicker _picker = ImagePicker();
  final PermissionService _permissionService = PermissionService();
  late final ReportService _reportService;

  String? _selectedCategory;
  String? _selectedTag;
  String? _imagePath;
  String? _videoPath;
  bool _isSubmitting = false;
  bool _showSuccess = false;
  bool _bucketReady = false;
  double? _currentLat;
  double? _currentLng;
  int? _detectedZone;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _reportService = widget.reportService ?? ReportService();
    _checkStorageBucket();
  }

  Future<void> _checkStorageBucket() async {
    final ready =
        await (widget.storageReadyResolver?.call() ??
            _supabase.ensureStorageBucket());
    if (mounted) setState(() => _bucketReady = ready);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // ================================================================
  // CÁMARA / GALERÍA: permiso contextual y fuente elegida por el usuario.
  // ================================================================
  Future<void> _pickImage() async {
    final source = await _chooseMediaSource('foto');
    if (source == null || !await _requestMediaAccess(source, 'una foto')) {
      return;
    }
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null && mounted) setState(() => _imagePath = photo.path);
    } catch (e) {
      debugPrint('ReportFormScreen image picker error: $e');
    }
  }

  Future<void> _pickVideo() async {
    final source = await _chooseMediaSource('video');
    if (source == null || !await _requestMediaAccess(source, 'un video')) {
      return;
    }
    try {
      final XFile? video = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null && mounted) setState(() => _videoPath = video.path);
    } catch (e) {
      debugPrint('ReportFormScreen video picker error: $e');
    }
  }

  Future<ImageSource?> _chooseMediaSource(String mediaLabel) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Tomar $mediaLabel'),
              subtitle: const Text('Solicita acceso a la cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Elegir $mediaLabel existente'),
              subtitle: const Text('Acceso solo al contenido que selecciones'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _requestMediaAccess(
    ImageSource source,
    String mediaLabel,
  ) async {
    if (!mounted) return false;
    final explanation = source == ImageSource.camera
        ? 'SafeZone necesita la cámara para capturar $mediaLabel y adjuntarlo a tu reporte.'
        : 'SafeZone abrirá el selector para adjuntar $mediaLabel que ya existe en tu dispositivo.';
    final continueRequest =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              source == ImageSource.camera ? 'Usar cámara' : 'Elegir archivo',
            ),
            content: Text(explanation),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!continueRequest) return false;
    final result = source == ImageSource.camera
        ? await _permissionService.requestCameraPermission()
        : await _permissionService.requestPhotosPermission();
    if (result == AppPermissionResult.granted) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se otorgó el permiso solicitado.')),
      );
    }
    return false;
  }

  // ================================================================
  // GEOLOCALIZACIÓN
  // ================================================================
  Future<bool> _obtenerUbicacion() async {
    setState(() => _isLocating = true);
    try {
      if (!await _permissionService.hasLocationPermission()) {
        if (!mounted) return false;
        final shouldRequest =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Ubicación del reporte'),
                content: const Text(
                  'Necesitamos tu ubicación para situar este reporte en el mapa. '
                  'No se usa como marcador público de tu ubicación personal.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Permitir'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!shouldRequest) return false;
        final result = await _permissionService.requestLocationPermission();
        if (result != AppPermissionResult.granted) return false;
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
          // La zona es la elección declarada por el usuario. El GPS aporta la
          // coordenada del reporte, pero no infiere límites inexistentes.
          _detectedZone = widget.zone;
          _isLocating = false;
        });
      }
      return true;
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ================================================================
  // ENVÍO DEL REPORTE
  // ================================================================
  Future<void> _submitReport() async {
    if (_isSubmitting) return;
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

    if (_selectedTag == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona el nivel de gravedad'),
          backgroundColor: AppTheme.warningYellow,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    if (widget.locationResolver case final resolver?) {
      final coordinates = await resolver();
      if (coordinates == null) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }
      _currentLat = coordinates.latitude;
      _currentLng = coordinates.longitude;
      _detectedZone = widget.zone;
    } else if (!await _obtenerUbicacion()) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    final result = await _reportService.createReport(
      ReportDraft(
        userCode: widget.userCode,
        zone: widget.zone,
        category: _selectedCategory!,
        description: _descriptionController.text.trim(),
        severity: _selectedTag!,
        latitude: _currentLat,
        longitude: _currentLng,
      ),
      localImagePath: _imagePath,
      localVideoPath: _videoPath,
    );

    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    unawaited(SoundService().play('report_sent'));

    setState(() {
      _isSubmitting = false;
      _showSuccess = true;
      _selectedCategory = null;
      _selectedTag = null;
      _imagePath = null;
      _videoPath = null;
      _descriptionController.clear();
      _currentLat = null;
      _currentLng = null;
      _detectedZone = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte enviado correctamente'),
        backgroundColor: AppTheme.safeGreen,
      ),
    );

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Incidente'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE65100), AppTheme.sectionReportar],
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
            child: const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: AppTheme.safeGreen,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '¡Reporte Enviado!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu reporte ya está visible en el Muro\ny en el Mapa de Riesgo de Collique',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              if (mounted) setState(() => _showSuccess = false);
            },
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
          const Text(
            '¿Qué está pasando?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 5
                  : constraints.maxWidth >= 480
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ReportFormConfig.categories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 150,
                ),
                itemBuilder: (context, index) {
                  final category = ReportFormConfig.categories[index];
                  return _ReportCategoryCard(
                    category: category,
                    isSelected: _selectedCategory == category.value,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      unawaited(SoundService().play('button_click'));
                      setState(() => _selectedCategory = category.value);
                    },
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),

          // ==========================================
          // 2. NIVEL DE GRAVEDAD (TAG)
          // ==========================================
          const Text(
            'Nivel de gravedad',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...ReportFormConfig.severities.map((severity) {
            final isSelected = _selectedTag == severity.value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                unawaited(SoundService().play('button_click'));
                if (mounted) {
                  setState(() => _selectedTag = severity.value);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryGreen
                        : Colors.grey[200]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected
                          ? AppTheme.primaryGreen
                          : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: severity.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  severity.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            severity.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
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
          const Text(
            'Describe lo que viste',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText:
                  'Ej: Vi una moto sospechosa dando vueltas en la Av. Revolución...',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),

          const SizedBox(height: 16),

          // ==========================================
          // 5. SUBIR EVIDENCIA
          // ==========================================
          const Text(
            'Sube evidencia (opcional)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
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
                      color: _imagePath != null
                          ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _imagePath != null
                            ? AppTheme.primaryGreen
                            : Colors.grey[300]!,
                        width: _imagePath != null ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _imagePath != null
                              ? Icons.check_circle
                              : Icons.camera_alt_outlined,
                          color: _imagePath != null
                              ? AppTheme.primaryGreen
                              : Colors.grey[400],
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _imagePath != null ? 'Foto lista' : 'Tomar Foto',
                          style: TextStyle(
                            fontSize: 12,
                            color: _imagePath != null
                                ? AppTheme.primaryGreen
                                : Colors.grey[500],
                          ),
                        ),
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
                      color: _videoPath != null
                          ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _videoPath != null
                            ? AppTheme.primaryGreen
                            : Colors.grey[300]!,
                        width: _videoPath != null ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _videoPath != null
                              ? Icons.check_circle
                              : Icons.videocam_outlined,
                          color: _videoPath != null
                              ? AppTheme.primaryGreen
                              : Colors.grey[400],
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _videoPath != null ? 'Video listo' : 'Grabar Video',
                          style: TextStyle(
                            fontSize: 12,
                            color: _videoPath != null
                                ? AppTheme.primaryGreen
                                : Colors.grey[500],
                          ),
                        ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isLocating
                            ? 'Obteniendo ubicación...'
                            : _currentLat != null
                            ? '📍 Ubicación capturada'
                            : 'La ubicación se capturará al enviar',
                        style: TextStyle(
                          fontSize: 12,
                          color: _currentLat != null
                              ? AppTheme.safeGreen
                              : Colors.grey[500],
                        ),
                      ),
                      if (_detectedZone != null && _detectedZone! > 0)
                        Text(
                          LocationService.zoneName(_detectedZone!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                LocationService.zoneColors[_detectedZone! - 1],
                          ),
                        ),
                    ],
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSubmitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isLocating
                              ? 'Obteniendo ubicación...'
                              : 'Enviando...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'ENVIAR REPORTE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Tu identidad permanecerá anónima',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ReportCategoryCard extends StatelessWidget {
  final ReportCategoryOption category;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReportCategoryCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: category.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? category.color : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(child: _buildIllustration()),
              const SizedBox(height: 8),
              Text(
                category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? category.color : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIllustration() {
    final asset = category.illustrationAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildIconFallback(),
      );
    }
    return _buildIconFallback();
  }

  Widget _buildIconFallback() {
    return Center(
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: category.color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(category.fallbackIcon, size: 38, color: category.color),
      ),
    );
  }
}
