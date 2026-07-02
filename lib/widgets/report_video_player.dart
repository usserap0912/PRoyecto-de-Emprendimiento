import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Widget reproductor de video para evidencias en reportes.
/// Reproduce en bucle videos de hasta 15 segundos con overlay play/pausa.
class ReportVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const ReportVideoPlayer({super.key, required this.videoUrl});

  @override
  State<ReportVideoPlayer> createState() => _ReportVideoPlayerState();
}

class _ReportVideoPlayerState extends State<ReportVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
          _controller.setLooping(true); // Reproducción en bucle infinito
        });
        _controller.play();
      }).catchError((error) {
        if (!mounted) return;
        setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose(); // Libera el buffer del video de forma segura
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, size: 32, color: Colors.white38),
              SizedBox(height: 8),
              Text(
                'Error al cargar la evidencia en video',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return _isInitialized
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(_controller),
                  _VideoPlayPauseOverlay(controller: _controller),
                  // Barra de progreso
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFC3110C),
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
  }
}

/// Overlay táctil para play/pausa con animación
class _VideoPlayPauseOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoPlayPauseOverlay({required this.controller});

  @override
  State<_VideoPlayPauseOverlay> createState() => _VideoPlayPauseOverlayState();
}

class _VideoPlayPauseOverlayState extends State<_VideoPlayPauseOverlay> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.controller.value.isPlaying
              ? widget.controller.pause()
              : widget.controller.play();
        });
      },
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            reverseDuration: const Duration(milliseconds: 200),
            child: widget.controller.value.isPlaying
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 60.0,
                        semanticLabel: 'Reproducir',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
