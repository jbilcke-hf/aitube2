// lib/widgets/video_player_widget.dart

import 'dart:async';
import 'package:aitube2/config/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:video_player/video_player.dart';
import '../models/video_result.dart';
import '../services/clip_queue_manager.dart';
import '../theme/colors.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoResult video;
  final String? initialThumbnailUrl;
  final bool autoPlay;
  final double borderRadius;
  final VoidCallback? onVideoLoaded;

  const VideoPlayerWidget({
    super.key,
    required this.video,
    this.initialThumbnailUrl,
    this.autoPlay = true,
    this.borderRadius = 12,
    this.onVideoLoaded,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final ClipQueueManager _queueManager;
  VideoPlayerController? _currentController;
  VideoPlayerController? _nextController;
  VideoClip? _currentClip;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isInitialLoad = true;
    

  double _loadingProgress = 0.0;
  Timer? _progressTimer;
  Timer? _debugTimer;
  Timer? _playbackTimer;  // New timer for tracking playback duration
  bool _isDisposed = false;

  Duration _currentPlaybackPosition = Duration.zero;
  Timer? _positionTrackingTimer;

  bool _startedInitialPlayback = false;
  Timer? _nextClipCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    // if (kDebugMode) { _startDebugPrinting(); }
  }

  void _startNextClipCheck() {
    _nextClipCheckTimer?.cancel();
    _nextClipCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isDisposed || !_isPlaying) {
        timer.cancel();
        return;
      }

      final nextClip = _queueManager.nextReadyClip;
      if (nextClip != null) {
        timer.cancel();
        _onVideoCompleted();
      }
    });
  }

  void _checkBufferAndStartPlayback() {
    if (_isDisposed || _startedInitialPlayback) return;

    final readyClips = _queueManager.clipBuffer.where((c) => c.isReady).length;
    final totalClips = _queueManager.clipBuffer.length;
    final bufferPercentage = (readyClips / totalClips * 100);

    if (bufferPercentage >= Configuration.instance.minimumBufferPercentToStartPlayback) {
      _startedInitialPlayback = true;
      _startInitialPlayback();
    } else {
      // Schedule another check
      Future.delayed(const Duration(milliseconds: 50), _checkBufferAndStartPlayback);
    }
  }

  Future<void> _startInitialPlayback() async {
    final nextClip = _queueManager.currentClip;
    if (nextClip?.isReady == true && !nextClip!.isPlaying) {
      _queueManager.startPlayingClip(nextClip);
      await _playClip(nextClip);
    }
    
    setState(() {
      _isLoading = false;
      _isInitialLoad = false;
    });
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _nextClipCheckTimer?.cancel();

    _playbackTimer = Timer(Configuration.instance.actualClipPlaybackDuration, () {
      if (_isDisposed || !_isPlaying) return;
      
      final nextClip = _queueManager.nextReadyClip;
      
      if (nextClip != null) {
        _onVideoCompleted();
      } else {
        // Reset current clip
        _currentController?.seekTo(Duration.zero);
        _currentPlaybackPosition = Duration.zero;
        
        // Start checking for next clip availability
        _startNextClipCheck();
      }
    });

    _startPositionTracking();
  }

  void _startPositionTracking() {
    _positionTrackingTimer?.cancel();
    _positionTrackingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isDisposed || !_isPlaying) return;
      
      final controller = _currentController;
      if (controller != null && controller.value.isInitialized) {
        _currentPlaybackPosition = controller.value.position;
      }
    });
  }

  void _togglePlayback() {
    if (_isLoading) return;
    
    final controller = _currentController;
    if (controller == null) return;

    setState(() => _isPlaying = !_isPlaying);
    
    if (_isPlaying) {
      // Restore previous position before playing
      controller.seekTo(_currentPlaybackPosition);
      controller.play();
      _startPlaybackTimer();
    } else {
      controller.pause();
      _playbackTimer?.cancel();
      _positionTrackingTimer?.cancel();
    }
  }

  Future<void> _playClip(VideoClip clip) async {
    if (_isDisposed || clip.base64Data == null) return;

    try {
      VideoPlayerController? newController;
      
      if (_nextController != null) {
        debugPrint('Using preloaded controller for clip ${clip.seed}');
        newController = _nextController;
        _nextController = null;
      } else {
        debugPrint('Creating new controller for clip ${clip.seed}');
        newController = VideoPlayerController.networkUrl(
          Uri.parse(clip.base64Data!),
        );
        await newController.initialize();
      }

      if (_isDisposed || newController == null) {
        newController?.dispose();
        return;
      }

      newController.setLooping(true);
      newController.setVolume(0.0);
      newController.setPlaybackSpeed(Configuration.instance.clipPlaybackSpeed);

      final oldController = _currentController;
      final oldClip = _currentClip;

      _queueManager.startPlayingClip(clip);
      _currentPlaybackPosition = Duration.zero; // Reset for new clip

      setState(() {
        _currentController = newController;
        _currentClip = clip;
        _isPlaying = widget.autoPlay;
      });

      if (widget.autoPlay) {
        await newController.play();
        debugPrint('Started playback of clip ${clip.seed}');
        _startPlaybackTimer();
      }

      await oldController?.dispose();
      if (oldClip != null && oldClip != clip) {
        _queueManager.markCurrentClipAsPlayed();
      }

      widget.onVideoLoaded?.call();
      await _preloadNextClip();
      _ensureBufferFull();

    } catch (e) {
      debugPrint('Error playing clip: $e');
      if (!_isDisposed) {
        setState(() => _isLoading = true);
        await Future.delayed(const Duration(milliseconds: 500));
        await _waitForClipAndPlay();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _currentController?.dispose();
    _nextController?.dispose();
    _progressTimer?.cancel();
    _debugTimer?.cancel();
   _playbackTimer?.cancel();
    _nextClipCheckTimer?.cancel();
    _positionTrackingTimer?.cancel();
    _queueManager.dispose();
    super.dispose();
  }

  //////////////////////////


  Future<void> _onVideoCompleted() async {
    if (_isDisposed) return;

    debugPrint('\nHandling video completion');
    _playbackTimer?.cancel();  // Cancel current playback timer
    
    // Get next clip before cleaning up current
    final nextClip = _queueManager.nextReadyClip;
    if (nextClip == null) {
      // debugPrint('No next clip ready, resetting current playback');
      _currentController?.seekTo(Duration.zero);
      _startPlaybackTimer();  // Restart playback timer
      return;
    }

    // Mark current as played and move to history
    if (_currentClip != null) {
      // debugPrint('Marking current clip ${_currentClip!.seed} as played');
      _queueManager.markCurrentClipAsPlayed();
      _currentClip = null;
    }

    // Important: Mark the next clip as playing BEFORE transitioning the video
    _queueManager.startPlayingClip(nextClip);
    // debugPrint('Marked next clip ${nextClip.seed} as playing in queue');

    // Transition to next clip
    if (_nextController != null) {
      // debugPrint('Using preloaded controller for next clip ${nextClip.seed}');
      final oldController = _currentController;
      setState(() {
        _currentController = _nextController;
        _nextController = null;
        _currentClip = nextClip;
        _isPlaying = true;
      });

      await _currentController?.play();
      _startPlaybackTimer();  // Start timer for new clip
      await oldController?.dispose();
      
      // Start preloading next
      await _preloadNextClip();
      
    } else {
      // debugPrint('No preloaded controller, playing next clip ${nextClip.seed} directly');
      await _playClip(nextClip);
    }
  }

  void _startDebugPrinting() {
    _debugTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isDisposed) {
        _queueManager.printQueueState();
        _logPlaybackStatus();
      }
    });
  }

  void _logPlaybackStatus() {
    if (kDebugMode) {
      final controller = _currentController;
      if (controller != null && controller.value.isInitialized) {
        final position = controller.value.position;
        final duration = controller.value.duration;
        debugPrint('Playback status: ${position.inSeconds}s / ${duration.inSeconds}s'
            ' (${_isPlaying ? "playing" : "paused"})');
        debugPrint('Current clip: ${_currentClip?.seed}, Next controller ready: ${_nextController != null}');
      }
    }
  }
  
  Future<void> _initializePlayer() async {
    if (_isDisposed) return;
    
    setState(() => _isLoading = true);

    if (_isInitialLoad) {
      _startLoadingProgress();
    }

    _queueManager = ClipQueueManager(
      video: widget.video,
      onQueueUpdated: () {
        _onQueueUpdated();
        // Check buffer status whenever queue updates
        _checkBufferAndStartPlayback();
      },
    );
    
    // Initialize queue manager but don't await it
    _queueManager.initialize().then((_) {
      if (!_isDisposed) {
        _waitForClipAndPlay();
      }
    });
  }

  void _startLoadingProgress() {
    _progressTimer?.cancel();
    _loadingProgress = 0.0;
    
    const totalDuration = Duration(seconds: 12);
    const updateInterval = Duration(milliseconds: 50);
    final steps = totalDuration.inMilliseconds / updateInterval.inMilliseconds;
    final increment = 1.0 / steps;

    _progressTimer = Timer.periodic(updateInterval, (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _loadingProgress += increment;
        if (_loadingProgress >= 1.0) {
          _progressTimer?.cancel();
        }
      });
    });
  }

  void _onQueueUpdated() {
    if (_isDisposed) return;
    setState(() {});
  }

  Future<void> _waitForClipAndPlay() async {
    if (_isDisposed) return;

    try {
      // Start periodic buffer checks
      _checkBufferAndStartPlayback();
    } catch (e) {
      debugPrint('Error waiting for clip: $e');
      if (!_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading video: $e')),
        );
        setState(() {
          _isLoading = false;
          _isInitialLoad = false;
        });
      }
    }
  }

  // New method to ensure buffer stays full
  void _ensureBufferFull() {
    if (_isDisposed) return;
    // debugPrint('Ensuring buffer is full...');
    // Let the queue manager know it should start new generations
    // This will trigger generation of new clips up to capacity
    _queueManager.fillBuffer();
  }

  Future<void> _preloadNextClip() async {
    if (_isDisposed) return;

    try {
      // Always try to preload the next ready clip
      final nextReadyClip = _queueManager.nextReadyClip;
      
      if (nextReadyClip?.base64Data != null && 
          nextReadyClip != _currentClip && 
          !nextReadyClip!.isPlaying) {
        // debugPrint('Preloading next clip (seed: ${nextReadyClip.seed})');
        
        final nextController = VideoPlayerController.networkUrl(
          Uri.parse(nextReadyClip.base64Data!),
        );

        await nextController.initialize();
        
        if (_isDisposed) {
          nextController.dispose();
          return;
        }

        // we always keep things looping. We never want any video to stop.
        nextController.setLooping(true);
        nextController.setVolume(0.0);
        nextController.setPlaybackSpeed(Configuration.instance.clipPlaybackSpeed);

        _nextController?.dispose();
        _nextController = nextController;
        
        // debugPrint('Successfully preloaded next clip');
      }
      
      // Always ensure we're generating new clips after preloading
      _ensureBufferFull();
      
    } catch (e) {
      debugPrint('Error preloading next clip: $e');
      _nextController?.dispose();
      _nextController = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controller = _currentController;
        final aspectRatio = controller?.value.aspectRatio ?? 16/9;
        final playerHeight = constraints.maxWidth / aspectRatio;

        return SizedBox(
          width: constraints.maxWidth,
          height: playerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base layer: Placeholder or Video
              ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: Container(
                  color: AiTubeColors.surfaceVariant,
                  child: controller?.value.isInitialized ?? false
                      ? VideoPlayer(controller!)
                      : _buildPlaceholder(),
                ),
              ),

              // Loading overlay with translucent background
              if (_isLoading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Container(
                    color: Colors.black54, // Semi-transparent overlay
                    child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: 16),
                                Text(
                                  'Generating video...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                ),
              ),

            // Play/Pause button overlay
            if (controller?.value.isInitialized ?? false)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: GestureDetector(
                    onTap: _togglePlayback,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                _buildBufferStatus(true),
              // Debug stats overlay
              /*
              if (kDebugMode)
                Positioned(
                  right: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatQueueStats(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              */
            ],
          ),
        );
      },
    );
  }

  String _formatQueueStats() {
    final stats = _queueManager.getBufferStats();
    final currentClipInfo = _currentClip != null 
        ? '\nPlaying: ${_currentClip!.seed}'
        : '';
    final nextClipInfo = _nextController != null
        ? '\nNext clip preloaded'
        : '';
    
    return 'Queue: ${stats['readyClips']}/${stats['bufferSize']} ready\n'
           'Gen: ${stats['activeGenerations']} active'
           '$currentClipInfo$nextClipInfo';
  }

  Widget _buildPlaceholder() {
    if (widget.initialThumbnailUrl?.isEmpty ?? true) {
      return const Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 64,
          color: AiTubeColors.onSurfaceVariant,
        ),
      );
    }

    try {
      if (widget.initialThumbnailUrl!.startsWith('data:image')) {
        final uri = Uri.parse(widget.initialThumbnailUrl!);
        final base64Data = uri.data?.contentAsBytes();
        
        if (base64Data == null) {
          throw Exception('Invalid image data');
        }

        return Image.memory(
          base64Data,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildErrorPlaceholder(),
        );
      }

      return Image.network(
        widget.initialThumbnailUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildErrorPlaceholder(),
      );
    } catch (e) {
      return _buildErrorPlaceholder();
    }
  }

   Widget _buildBufferStatus(bool showDuringLoading) {
    final readyOrPlayingClips = _queueManager.clipBuffer.where((c) => c.isReady || c.isPlaying).length;
    final totalClips = _queueManager.clipBuffer.length;
    final bufferPercentage = (readyOrPlayingClips / totalClips * 100).round();

    // since we are playing clips at a reduced speed, they each last "longer"
    // eg a video playing back at 0.5 speed will see its duration multiplied by 2
    final actualDurationPerClip = Configuration.instance.actualClipPlaybackDuration;

    final remainingSeconds = readyOrPlayingClips * actualDurationPerClip.inSeconds;

    // Don't show 0% during initial loading
    if (!showDuringLoading && bufferPercentage == 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getBufferIcon(bufferPercentage),
              color: _getBufferStatusColor(bufferPercentage),
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _isLoading 
                ? 'Buffering $bufferPercentage%'
                : '$bufferPercentage% (${remainingSeconds}s)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBufferIcon(int percentage) {
    if (percentage >= 40) return Icons.network_wifi;
    if (percentage >= 30) return Icons.network_wifi_3_bar;
    if (percentage >= 20) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  Color _getBufferStatusColor(int percentage) {
    if (percentage >= 30) return Colors.green;
    if (percentage >= 20) return Colors.orange;
    return Colors.red;
  }

  Widget _buildErrorPlaceholder() {
    return const Center(
      child: Icon(
        Icons.broken_image,
        size: 64,
        color: AiTubeColors.onSurfaceVariant,
      ),
    );
  }
}