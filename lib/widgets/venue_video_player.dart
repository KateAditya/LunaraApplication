import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/theme.dart';

class VenueVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool loop;

  const VenueVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = true,
    this.loop = true,
  });

  @override
  State<VenueVideoPlayer> createState() => _VenueVideoPlayerState();
}

class _VenueVideoPlayerState extends State<VenueVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    debugPrint('[VenueVideoPlayer] Initializing: ${widget.videoUrl}');
    try {
      final uri = Uri.parse(widget.videoUrl);
      final ctrl = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: const {
          'Connection': 'keep-alive',
        },
      );

      ctrl.addListener(() {
        if (ctrl.value.hasError && mounted) {
          debugPrint('[VenueVideoPlayer] Playback error: ${ctrl.value.errorDescription}');
          setState(() {
            _hasError = true;
            _errorMessage = ctrl.value.errorDescription;
          });
        }
      });

      await ctrl.initialize();
      debugPrint('[VenueVideoPlayer] Initialized OK — size: ${ctrl.value.size}');

      if (!mounted) {
        ctrl.dispose();
        return;
      }

      _controller = ctrl;
      _controller!.setVolume(0);
      _controller!.setLooping(widget.loop);

      setState(() => _isInitialized = true);

      if (widget.autoPlay) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _controller!.play();
      }
    } catch (e, st) {
      debugPrint('[VenueVideoPlayer] Init failed: $e\n$st');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
      _errorMessage = null;
    });
    await _controller?.dispose();
    _controller = null;
    await _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 44),
              const SizedBox(height: 10),
              const Text(
                'Video unavailable',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, color: LunaraTheme.accentVivid, size: 18),
                label: const Text('Retry', style: TextStyle(color: LunaraTheme.accentVivid)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: CircularProgressIndicator(
            color: LunaraTheme.accentVivid,
            strokeWidth: 2,
          ),
        ),
      );
    }

    // Use SizedBox.expand so the video fills whatever space the parent gives
    // (e.g. the fixed-height SliverAppBar). FittedBox keeps the aspect ratio
    // without fighting the parent constraints.
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
          // Dark scrim overlay when paused
          if (!_controller!.value.isPlaying)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
            ),
          // Centre play button
          if (!_controller!.value.isPlaying)
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(14),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
          // Play / pause button (bottom-right)
          Positioned(
            bottom: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _controller!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          // Mute/unmute (bottom-left)
          Positioned(
            bottom: 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  final isMuted = _controller!.value.volume == 0;
                  _controller!.setVolume(isMuted ? 1.0 : 0.0);
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _controller!.value.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
