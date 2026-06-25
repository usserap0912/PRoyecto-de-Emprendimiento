import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/services/report_service.dart';
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
  final ReportService _reportService = ReportService();
  final SupabaseService _supabase = SupabaseService();
  final ImagePicker _picker = ImagePicker();

  String? _selectedCategory;
  String? _selectedTag;
  String? _imagePath;
  String? _videoPath;
  bool _isSubmitting = false;
  bool _showSuccess = false;
  bool _bucketReady = false;

  @override
  void initState() {
    super.initState();
    _checkStorageBucket();
  }

  Future<void> _checkStorageBucket() async {
    final ready = await _supabase.ensureStorageBucket();
    if (mounted) setState(() => _bucketReady = ready);
  }

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

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null && mounted) {
        setState(() => _imagePath = photo.path);
      }
    } catch (e) {
      if (!mounted) return;
      final XFile? gallery = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (gallery != null && mounted) {
        setState(() => _imagePath = gallery.path);
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null && mounted) {
        setState(() => _videoPath = video.path);
      }
    } catch (e) {
      // Fallback
    }
  }

  Future<void> _submitReport() async {
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

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    try {
      final report = Report(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        userCode: widget.userCode,
        zone: widget.zone,
        category: _selectedCategory!,
        description: _descriptionController.text.trim(),
        imageUrl: _imagePath,
        videoUrl: _videoPath,
        tag: _selectedTag ?? 'amarillo',
        createdAt: DateTime.now(),
      );

      final success = await _reportService.createReport(
        report,
        localImagePath: _imagePath,
        localVideoPath: _videoPath,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _showSuccess = success;
          if (success) {
            _selectedCategory = null;
            _selectedTag = null;
            _imagePath = null;
            _videoPath = null;
            _descriptionController.clear();
          }
        });

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al enviar el reporte. Intenta de nuevo.'),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
        } else {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showSuccess = false);
          });
        }
      }
    } catch (e) {
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
            'Tu reporte ya está visible en el Muro\npara que toda la comunidad lo vea',
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
          const Text(
            '¿Qué está pasando?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat['key'];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (mounted) {
                      setState(() => _selectedCategory = cat['key'] as String);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (cat['color'] as Color).withValues(alpha: 0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? cat['color'] as Color
                            : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          cat['icon'] as IconData,
                          color: isSelected
                              ? cat['color'] as Color
                              : Colors.grey[400],
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? cat['color'] as Color
                                : Colors.grey[600],
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

          const Text(
            'Nivel de gravedad',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ..._tags.map((tag) {
            final isSelected = _selectedTag == tag['key'];
            return GestureDetector(
              onTap: () {
                if (mounted) {
                  setState(() => _selectedTag = tag['key'] as String);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isSelected ? AppTheme.primaryGreen : Colors.grey[200]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected ? AppTheme.primaryGreen : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tag['label'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: isSelected ? Colors.black87 : Colors.grey[600],
                          ),
                        ),
                        Text(
                          tag['desc'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

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

          const SizedBox(height: 32),

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
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
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
