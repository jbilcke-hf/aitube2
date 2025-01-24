// lib/services/clip_queue_manager.dart

import 'dart:async';
import 'package:async/async.dart' show unawaited;
import 'package:aitube2/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import '../models/video_result.dart';
import '../services/websocket_api_service.dart';
import '../services/cache_service.dart';
import '../utils/seed.dart';

enum ClipState {
  generationPending,
  generationInProgress,
  generatedAndReadyToPlay,
  generatedAndPlaying,
  failedToGenerate,
  generatedAndPlayed
}

class VideoClip {
  final String id;
  final String prompt;
  final int seed;
  ClipState state;
  String? base64Data;
  Timer? retryTimer;
  Completer<void>? generationCompleter;
  DateTime? generationStartTime;
  DateTime? generationEndTime;
  DateTime? playStartTime;
  int retryCount = 0;
  static const maxRetries = 3;

  VideoClip({
    String? id,
    required this.prompt,
    required this.seed,
    this.state = ClipState.generationPending,
    this.base64Data,
  }):  id = id ?? const Uuid().v4(); 

  bool get isReady => state == ClipState.generatedAndReadyToPlay;
  bool get isPending => state == ClipState.generationPending;
  bool get isGenerating => state == ClipState.generationInProgress;
  bool get isPlaying => state == ClipState.generatedAndPlaying;
  bool get hasFailed => state == ClipState.failedToGenerate;
  bool get hasPlayed => state == ClipState.generatedAndPlayed;
  bool get canRetry => retryCount < maxRetries;

  Duration? get generationDuration {
    if (generationStartTime == null) return null;
    if (isGenerating) {
      return DateTime.now().difference(generationStartTime!);
    }
    if (isReady || isPlaying || hasPlayed) {
      return generationEndTime?.difference(generationStartTime!);
    }
    return null;
  }

  Duration? get playbackDuration {
    if (playStartTime == null) return null;
    return DateTime.now().difference(playStartTime!);
  }

  void startPlaying() {
    if (state == ClipState.generatedAndReadyToPlay) {
      state = ClipState.generatedAndPlaying;
      playStartTime = DateTime.now();
    }
  }

  void finishPlaying() {
    if (state == ClipState.generatedAndPlaying) {
      state = ClipState.generatedAndPlayed;
    }
  }

  void completeGeneration() {
    if (state == ClipState.generationInProgress) {
      generationEndTime = DateTime.now();
      state = ClipState.generatedAndReadyToPlay;
    }
  }

  @override
  String toString() => 'VideoClip(seed: $seed, state: $state, retryCount: $retryCount)';
}

class ClipQueueManager {
  static const bool _showLogsInDebugMode = false;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration clipTimeout = Duration(seconds: 90);
  static const Duration generationTimeout = Duration(seconds: 60);
  
  final VideoResult video;
  final WebSocketApiService _websocketService;
  final CacheService _cacheService;
  final void Function()? onQueueUpdated;
  
  final List<VideoClip> _clipBuffer = [];
  final List<VideoClip> _clipHistory = [];
  final _activeGenerations = <String>{};
  Timer? _bufferCheckTimer;
  bool _isDisposed = false;

  DateTime? _lastSuccessfulGeneration;
  final _generationTimes = <Duration>[];
  static const _maxStoredGenerationTimes = 10;

  final String videoId;

  DateTime? _lastStateLogTime;
  Map<String, dynamic>? _lastLoggedState;

  ClipQueueManager({
    required this.video,
    WebSocketApiService? websocketService,
    CacheService? cacheService,
    this.onQueueUpdated,
  }) : videoId = video.id,
       _websocketService = websocketService ?? WebSocketApiService(),
       _cacheService = cacheService ?? CacheService();

  bool get canStartNewGeneration => 
      _activeGenerations.length < Configuration.instance.renderQueueMaxConcurrentGenerations;
  int get pendingGenerations => _clipBuffer.where((c) => c.isPending).length;
  int get activeGenerations => _activeGenerations.length;
  VideoClip? get currentClip => _clipBuffer.firstWhereOrNull((c) => c.isReady || c.isPlaying);
  VideoClip? get nextReadyClip => _clipBuffer.where((c) => c.isReady && !c.isPlaying).firstOrNull;
  bool get hasReadyClips => _clipBuffer.any((c) => c.isReady);
  List<VideoClip> get clipBuffer => List.unmodifiable(_clipBuffer);
  List<VideoClip> get clipHistory => List.unmodifiable(_clipHistory);

  Future<void> initialize() async {
    if (_isDisposed) return;
    
    _logStateChange('initialize:start');
    _clipBuffer.clear();
    
    try {
      final bufferSize = Configuration.instance.renderQueueBufferSize;
      while (_clipBuffer.length < bufferSize) {
        if (_isDisposed) return;
        
        final newClip = VideoClip(
          prompt: "${video.title}\n${video.description}",
          seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
        );
        _clipBuffer.add(newClip);
        _logEvent('Added initial clip ${newClip.seed} to buffer');
      }

      if (_isDisposed) return;

      _startBufferCheck();
      await _fillBuffer();
      _logEvent('Initialization complete. Buffer size: ${_clipBuffer.length}');
      printQueueState();
    } catch (e) {
      _logEvent('Initialization error: $e');
      rethrow;
    }

    _logStateChange('initialize:complete');
  }

  void _startBufferCheck() {
    _bufferCheckTimer?.cancel();
    _bufferCheckTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) {
        if (!_isDisposed) {
          _fillBuffer();
        }
      },
    );
    _logEvent('Started buffer check timer');
  }

  void markClipAsPlayed(String clipId) {
    _logStateChange('markAsPlayed:start');
    final playingClip = _clipBuffer.firstWhereOrNull((c) => c.id == clipId);
    if (playingClip != null) {
      playingClip.finishPlaying();
      
      final cacheKey = "${video.id}_${playingClip.seed}";
      unawaited(_cacheService.delete(cacheKey).catchError((e) {
        debugPrint('Failed to remove clip ${playingClip.seed} from cache: $e');
      }));
      
      _reorderBufferByPriority();
      _fillBuffer();
      onQueueUpdated?.call();
    }
    _logStateChange('markAsPlayed:complete');
  }

  Future<void> _fillBuffer() async {
    if (_isDisposed) return;

    // First ensure we have the correct buffer size
    while (_clipBuffer.length < Configuration.instance.renderQueueBufferSize) {
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
      _logEvent('Added new clip ${newClip.seed} to maintain buffer size');
    }

    // Process played clips first
    final playedClips = _clipBuffer.where((clip) => clip.hasPlayed).toList();
    if (playedClips.isNotEmpty) {
      _processPlayedClips(playedClips);
    }
  
    // Remove failed clips and replace them
    final failedClips = _clipBuffer.where((clip) => clip.hasFailed && !clip.canRetry).toList();
    for (final clip in failedClips) {
      _clipBuffer.remove(clip);
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
    }

    // Clean up stuck generations
    _checkForStuckGenerations();

    // Get pending clips that aren't being generated
    final pendingClips = _clipBuffer
        .where((clip) => clip.isPending && !_activeGenerations.contains(clip.seed.toString()))
        .toList();

    // Calculate available generation slots
    final availableSlots = Configuration.instance.renderQueueMaxConcurrentGenerations - _activeGenerations.length;

    if (availableSlots > 0 && pendingClips.isNotEmpty) {
      final clipsToGenerate = pendingClips.take(availableSlots).toList();
      _logEvent('Starting ${clipsToGenerate.length} parallel generations');

      final generationFutures = clipsToGenerate.map((clip) => 
        _generateClip(clip).catchError((e) {
          debugPrint('Generation failed for clip ${clip.seed}: $e');
          return null;
        })
      ).toList();

      unawaited(
        Future.wait(generationFutures, eagerError: false).then((_) {
          if (!_isDisposed) {
            onQueueUpdated?.call();
            // Recursively ensure buffer stays full
            _fillBuffer();
          }
        })
      );
    }

    onQueueUpdated?.call();

    _logStateChange('fillBuffer:complete');
  }

  void _reorderBufferByPriority() {
    // First, extract all clips that aren't played
    final activeClips = _clipBuffer.where((c) => !c.hasPlayed).toList();
    
    // Sort clips by priority:
    // 1. Currently playing clips stay at their position
    // 2. Ready clips move to the front (right after playing clips)
    // 3. In-progress generations
    // 4. Pending generations
    // 5. Failed generations
    activeClips.sort((a, b) {
      // Helper function to get priority value for a state
      int getPriority(ClipState state) {
        switch (state) {
          case ClipState.generatedAndPlaying:
            return 0;
          case ClipState.generatedAndReadyToPlay:
            return 1;
          case ClipState.generationInProgress:
            return 2;
          case ClipState.generationPending:
            return 3;
          case ClipState.failedToGenerate:
            return 4;
          case ClipState.generatedAndPlayed:
            return 5;
        }
      }

      // Compare priorities
      final priorityA = getPriority(a.state);
      final priorityB = getPriority(b.state);
      
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      
      // If same priority, maintain relative order by keeping original indices
      return _clipBuffer.indexOf(a).compareTo(_clipBuffer.indexOf(b));
    });

    // Clear and refill the buffer with the sorted clips
    _clipBuffer.clear();
    _clipBuffer.addAll(activeClips);
  }

  void _processPlayedClips(List<VideoClip> playedClips) {
    for (final clip in playedClips) {
      _clipBuffer.remove(clip);
      _clipHistory.add(clip);
      
      // Add a new pending clip
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
      _logEvent('Replaced played clip ${clip.seed} with new clip ${newClip.seed}');
    }
    
    // Immediately trigger buffer fill to start generating new clips
    _fillBuffer();
  }

  void _checkForStuckGenerations() {
    final now = DateTime.now();
    var hadStuckGenerations = false;

    for (final clip in _clipBuffer) {
      if (clip.isGenerating && 
          clip.generationStartTime != null &&
          now.difference(clip.generationStartTime!) > clipTimeout) {
        hadStuckGenerations = true;
        _handleStuckGeneration(clip);
      }
    }

    if (hadStuckGenerations) {
      _logEvent('Cleaned up stuck generations. Active: ${_activeGenerations.length}');
    }
  }

  void _handleStuckGeneration(VideoClip clip) {
    _logEvent('Found stuck generation for clip ${clip.seed}');
    
    if (_activeGenerations.contains(clip.seed.toString())) {
      _activeGenerations.remove(clip.seed.toString());
    }
    
    clip.state = ClipState.failedToGenerate;
    
    if (clip.canRetry) {
      _scheduleRetry(clip);
    }
  }

  // Also reorder after retries
  void _scheduleRetry(VideoClip clip) {
    clip.retryTimer?.cancel();
    clip.retryTimer = Timer(retryDelay, () {
      if (!_isDisposed && clip.hasFailed) {
        _logEvent('Retrying clip ${clip.seed} (attempt ${clip.retryCount + 1}/${VideoClip.maxRetries})');
        clip.state = ClipState.generationPending;
        clip.generationCompleter = null;
        clip.generationStartTime = null;
        _reorderBufferByPriority(); // Add reordering here
        onQueueUpdated?.call();
        _fillBuffer();
      }
    });
  }

  Future<void> _generateClip(VideoClip clip) async {
    if (clip.isGenerating || clip.isReady || _isDisposed || !canStartNewGeneration) {
      return;
    }

    final clipSeed = clip.seed.toString();
    if (_activeGenerations.contains(clipSeed)) {
      _logEvent('Clip $clipSeed already generating');
      return;
    }

    _activeGenerations.add(clipSeed);
    clip.state = ClipState.generationInProgress;
    clip.generationCompleter = Completer<void>();
    clip.generationStartTime = DateTime.now();

    try {
      final cacheKey = "${video.id}_${clip.seed}";
      String? videoData;

      // Check if we're disposed before proceeding
      if (_isDisposed) {
        _logEvent('Cancelled generation of clip $clipSeed - manager disposed');
        return;
      }

      // Try cache first
      try {
        videoData = await _cacheService.getVideoData(cacheKey);
      } catch (e) {
        if (_isDisposed) return; // Check disposed state after each await
        debugPrint('Cache error for clip ${clip.seed}: $e');
      }

      if (videoData != null && !_isDisposed) {
        await _handleSuccessfulGeneration(clip, videoData, cacheKey);
        return;
      }

      if (_isDisposed) {
        _logEvent('Cancelled generation of clip $clipSeed - manager disposed after cache check');
        return;
      }

      // Generate new video with timeout
      videoData = await _websocketService.generateVideo(
        video,
        seed: clip.seed,
      ).timeout(generationTimeout);

      if (!_isDisposed) {
        await _handleSuccessfulGeneration(clip, videoData, cacheKey);
      }

    } catch (e) {
      if (!_isDisposed) {
        _handleFailedGeneration(clip, e);
      }
    } finally {
      _cleanupGeneration(clip);
    }
  }

  Future<void> _handleSuccessfulGeneration(
    VideoClip clip,
    String videoData,
    String cacheKey,
  ) async {
    if (_isDisposed) return;
    
    clip.base64Data = videoData;
    clip.completeGeneration();
    
    // Only complete the completer if it exists and isn't already completed
    if (clip.generationCompleter != null && !clip.generationCompleter!.isCompleted) {
      clip.generationCompleter!.complete();
    }
    
    // Cache only if the clip isn't already played
    if (!clip.hasPlayed) {
      unawaited(_cacheService.cacheVideoData(cacheKey, videoData).catchError((e) {
        debugPrint('Failed to cache clip ${clip.seed}: $e');
      }));
    }

    // Reorder the buffer to prioritize this newly ready clip
    _reorderBufferByPriority();
    
    _updateGenerationStats(clip);
    onQueueUpdated?.call();
  }


  void _handleFailedGeneration(VideoClip clip, dynamic error) {
    if (_isDisposed) return;
    _logStateChange('generation:failed:start');
    clip.state = ClipState.failedToGenerate;
    clip.retryCount++;
    
    // Only complete with error if the completer exists and isn't completed
    if (clip.generationCompleter != null && !clip.generationCompleter!.isCompleted) {
      clip.generationCompleter!.completeError(error);
    }
    
    if (clip.canRetry) {
      _scheduleRetry(clip);
    }
    _logStateChange('generation:failed:complete');
  }

  void _cleanupGeneration(VideoClip clip) {
    if (!_isDisposed) {
      _activeGenerations.remove(clip.seed.toString());
      onQueueUpdated?.call();
      _fillBuffer();
    }
  }

  void _updateGenerationStats(VideoClip clip) {
    if (clip.generationStartTime != null) {
      final duration = DateTime.now().difference(clip.generationStartTime!);
      _generationTimes.add(duration);
      if (_generationTimes.length > _maxStoredGenerationTimes) {
        _generationTimes.removeAt(0);
      }
      _lastSuccessfulGeneration = DateTime.now();
    }
  }

  Duration? _getAverageGenerationTime() {
    if (_generationTimes.isEmpty) return null;
    final totalMs = _generationTimes.fold<int>(
      0, 
      (sum, duration) => sum + duration.inMilliseconds
    );
    return Duration(milliseconds: totalMs ~/ _generationTimes.length);
  }

  void markCurrentClipAsPlayed() {
     _logStateChange('markAsPlayed:start');
    final playingClip = _clipBuffer.firstWhereOrNull((c) => c.isPlaying);
    if (playingClip != null) {
      playingClip.finishPlaying();
      
      // Remove from cache when played
      final cacheKey = "${video.id}_${playingClip.seed}";
      unawaited(_cacheService.delete(cacheKey).catchError((e) {
        debugPrint('Failed to remove clip ${playingClip.seed} from cache: $e');
      }));
      
      _reorderBufferByPriority();
      _fillBuffer();
      onQueueUpdated?.call();
    }
     _logStateChange('markAsPlayed:complete');
  }

  void startPlayingClip(VideoClip clip) {
    _logStateChange('startPlaying:start');
    if (clip.isReady) {
      clip.startPlaying();
      onQueueUpdated?.call();
    }
    _logStateChange('startPlaying:complete');
  }

  void fillBuffer() {
    _logEvent('Manual buffer fill requested');
    _fillBuffer();
  }

  void printQueueState() {
    final ready = _clipBuffer.where((c) => c.isReady).length;
    final playing = _clipBuffer.where((c) => c.isPlaying).length;
    final generating = _activeGenerations.length;
    final pending = pendingGenerations;
    final failed = _clipBuffer.where((c) => c.hasFailed).length;
    
    _logEvent('\nQueue State:');
    _logEvent('Buffer size: ${_clipBuffer.length}');
    _logEvent('Ready: $ready, Playing: $playing, Generating: $generating, Pending: $pending, Failed: $failed');
    _logEvent('History size: ${_clipHistory.length}');
    
    for (var i = 0; i < _clipBuffer.length; i++) {
      final clip = _clipBuffer[i];
      final genDuration = clip.generationDuration;
      final playDuration = clip.playbackDuration;
      _logEvent('Clip $i: seed=${clip.seed}, state=${clip.state}, '
          'retries=${clip.retryCount}, generation time=${genDuration?.inSeconds}s'
          '${playDuration != null ? ", playing for ${playDuration.inSeconds}s" : ""}');
    }
  }

  Map<String, dynamic> getBufferStats() {
    final averageGeneration = _getAverageGenerationTime();
    return {
      'bufferSize': _clipBuffer.length,
      'historySize': _clipHistory.length,
      'activeGenerations': _activeGenerations.length,
      'pendingClips': pendingGenerations,
      'readyClips': _clipBuffer.where((c) => c.isReady).length,
      'failedClips': _clipBuffer.where((c) => c.hasFailed).length,
      'lastSuccessfulGeneration': _lastSuccessfulGeneration?.toString(),
      'averageGenerationTime': averageGeneration?.toString(),
      'clipStates': _clipBuffer.map((c) => c.state.toString()).toList(),
    };
  }
  
  void _logEvent(String message) {
    if (_showLogsInDebugMode && kDebugMode) {
      debugPrint('ClipQueue: $message');
    }
  }

  void _logGenerationStatus() {
    final pending = _clipBuffer.where((c) => c.isPending).length;
    final generating = _activeGenerations.length;
    final ready = _clipBuffer.where((c) => c.isReady).length;
    final playing = _clipBuffer.where((c) => c.isPlaying).length;
    
    _logEvent('''
      Buffer Status:
      - Pending: $pending
      - Generating: $generating
      - Ready: $ready
      - Playing: $playing
      - Active generations: ${_activeGenerations.join(', ')}
    ''');
  }

  void _logStateChange(String trigger) {
    if (_isDisposed) return;

    final currentState = {
      'readyClips': _clipBuffer.where((c) => c.isReady).length,
      'playingClips': _clipBuffer.where((c) => c.isPlaying).length,
      'generatingClips': _activeGenerations.length,
      'pendingClips': pendingGenerations,
      'failedClips': _clipBuffer.where((c) => c.hasFailed).length,
      'clipStates': _clipBuffer.map((c) => {
        'seed': c.seed,
        'state': c.state.toString(),
        'retryCount': c.retryCount,
        'genDuration': c.generationDuration?.inSeconds,
        'playDuration': c.playbackDuration?.inSeconds,
      }).toList(),
      'activeGenerations': List<String>.from(_activeGenerations),
      'historySize': _clipHistory.length,
    };

    // Only log if state has changed
    if (_lastLoggedState == null || 
        !_areStatesEqual(_lastLoggedState!, currentState) ||
        _shouldLogDueToTimeout()) {
      
      debugPrint('\n=== Queue State Change [$trigger] ===');
      debugPrint('Ready: ${currentState['readyClips']}');
      debugPrint('Playing: ${currentState['playingClips']}');
      debugPrint('Generating: ${currentState['generatingClips']}');
      debugPrint('Pending: ${currentState['pendingClips']}');
      debugPrint('Failed: ${currentState['failedClips']}');
      debugPrint('History: ${currentState['historySize']}');
      
      debugPrint('\nClip Details:');
      final clipStates = currentState['clipStates'] as List<Map<String, dynamic>>;
      for (var clipState in clipStates) {
        debugPrint('Clip ${clipState['seed']}: ${clipState['state']} '
            '(retries: ${clipState['retryCount']}, '
            'gen: ${clipState['genDuration']}s, '
            'play: ${clipState['playDuration']}s)');
      }

      final activeGenerations = currentState['activeGenerations'] as List<String>;
      if (activeGenerations.isNotEmpty) {
        debugPrint('\nActive Generations: ${activeGenerations.join(', ')}');
      }

      debugPrint('=====================================\n');

      _lastLoggedState = currentState;
      _lastStateLogTime = DateTime.now();
    }
  }

  bool _areStatesEqual(Map<String, dynamic> state1, Map<String, dynamic> state2) {
    return state1['readyClips'] == state2['readyClips'] &&
           state1['playingClips'] == state2['playingClips'] &&
           state1['generatingClips'] == state2['generatingClips'] &&
           state1['pendingClips'] == state2['pendingClips'] &&
           state1['failedClips'] == state2['failedClips'] &&
           state1['historySize'] == state2['historySize'] &&
           const ListEquality().equals(
             state1['activeGenerations'] as List,
             state2['activeGenerations'] as List
           );
  }

  bool _shouldLogDueToTimeout() {
    if (_lastStateLogTime == null) return true;
    // Force log every 30 seconds even if state hasn't changed
    return DateTime.now().difference(_lastStateLogTime!) > const Duration(seconds: 30);
  }

  Future<void> dispose() async {
    debugPrint('ClipQueueManager: Starting disposal for video $videoId');
    _isDisposed = true;

    // Cancel all timers first
    _bufferCheckTimer?.cancel();
    
    // Complete any pending generation completers
    for (var clip in _clipBuffer) {
      clip.retryTimer?.cancel();
      
      if (clip.isGenerating && 
          clip.generationCompleter != null && 
          !clip.generationCompleter!.isCompleted) {
        // Don't throw an error, just complete normally
        clip.generationCompleter!.complete();
      }
    }

    // Cancel any pending requests for this video
    if (videoId.isNotEmpty) {
      _websocketService.cancelRequestsForVideo(videoId);
    }

    // Clear all collections
    _clipBuffer.clear();
    _clipHistory.clear();
    _activeGenerations.clear();

    debugPrint('ClipQueueManager: Completed disposal for video $videoId');
  }
}