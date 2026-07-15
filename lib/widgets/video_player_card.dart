import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A self-contained looping video preview with play/pause + scrubber.
/// Plays a local file path. Handles its own lifecycle.
class VideoPlayerCard extends StatefulWidget {
  final String path;
  final String aspectRatio; // '16:9' | '9:16' | '1:1'
  final bool autoplay;

  const VideoPlayerCard({
    super.key,
    required this.path,
    this.aspectRatio = '16:9',
    this.autoplay = true,
  });

  @override
  State<VideoPlayerCard> createState() => _VideoPlayerCardState();
}

class _VideoPlayerCardState extends State<VideoPlayerCard> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerCard old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _controller?.dispose();
      _ready = false;
      _error = false;
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      if (widget.autoplay) await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double get _ratio {
    switch (widget.aspectRatio) {
      case '9:16':
        return 9 / 16;
      case '1:1':
        return 1;
      default:
        return 16 / 9;
    }
  }

  void _toggle() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratio =
        _ready && _controller != null ? _controller!.value.aspectRatio : _ratio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Container(
          color: Colors.black,
          child: _error
              ? const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white38, size: 40))
              : !_ready
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70),
                      ),
                    )
                  : GestureDetector(
                      onTap: _toggle,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller!),
                          _PlayOverlay(controller: _controller!),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF0A84FF),
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  const _PlayOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        if (value.isPlaying) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(14),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 40),
        );
      },
    );
  }
}
