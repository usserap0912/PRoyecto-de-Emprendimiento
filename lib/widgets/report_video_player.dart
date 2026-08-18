import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ReportVideoPlayer extends StatefulWidget {
  const ReportVideoPlayer({super.key, required this.videoUrl});
  final String videoUrl;

  @override
  State<ReportVideoPlayer> createState() => _ReportVideoPlayerState();
}

class _ReportVideoPlayerState extends State<ReportVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isMuted = true;
  double _audibleVolume = 1;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant ReportVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl == widget.videoUrl) return;
    _controller.removeListener(_onControllerChanged);
    _controller.pause();
    _controller.dispose();
    _isInitialized = false;
    _hasError = false;
    _initializeController();
  }

  void _initializeController() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.addListener(_onControllerChanged);
    _controller.initialize().then((_) async {
      await _controller.setLooping(false);
      await _controller.setVolume(0);
      if (mounted) setState(() => _isInitialized = true);
    }).catchError((_) {
      if (mounted) setState(() => _hasError = true);
    });
  }

  void _onControllerChanged() {
    if (mounted && _isInitialized) setState(() {});
  }

  Future<void> _togglePlayback() async {
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  Future<void> _toggleMute() async {
    _isMuted = !_isMuted;
    await _controller.setVolume(_isMuted ? 0 : _audibleVolume);
    if (mounted) setState(() {});
  }

  Future<void> _setVolume(double value) async {
    _audibleVolume = value;
    _isMuted = value == 0;
    await _controller.setVolume(value);
    if (mounted) setState(() {});
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Error al cargar la evidencia en video')),
      );
    }
    if (!_isInitialized) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final value = _controller.value;
    final durationMs = value.duration.inMilliseconds;
    final positionMs = value.position.inMilliseconds.clamp(0, durationMs);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: GestureDetector(
                onTap: _togglePlayback,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    if (!value.isPlaying)
                      const Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 64,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: value.isPlaying ? 'Pausar' : 'Reproducir',
                    onPressed: _togglePlayback,
                    color: Colors.white,
                    icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  Text(
                    '${_format(value.position)} / ${_format(value.duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Expanded(
                    child: Slider(
                      value: positionMs.toDouble(),
                      max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                      onChanged: (position) => _controller.seekTo(
                        Duration(milliseconds: position.round()),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _isMuted ? 'Activar sonido' : 'Silenciar',
                    onPressed: _toggleMute,
                    color: Colors.white,
                    icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                  ),
                  SizedBox(
                    width: 70,
                    child: Slider(
                      value: _isMuted ? 0 : _audibleVolume,
                      onChanged: _setVolume,
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
