// lib/screens/video_screen.dart
import 'package:aitube2/widgets/chat_widget.dart';
import 'package:flutter/material.dart';
import '../models/video_result.dart';
import '../services/websocket_api_service.dart';
import '../services/cache_service.dart';
import '../theme/colors.dart';
import '../widgets/video_player_widget.dart';

class VideoScreen extends StatefulWidget {
  final VideoResult video;

  const VideoScreen({
    super.key,
    required this.video,
  });

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  Future<String>? _captionFuture;
  final _websocketService = WebSocketApiService();
  final _cacheService = CacheService();
  bool _isConnected = false;
  late VideoResult _videoData;

  @override
  void initState() {
    super.initState();
    _videoData = widget.video;
    _websocketService.addSubscriber(widget.video.id);
    _initializeConnection();
    _loadCachedThumbnail();
  }

  Future<void> _loadCachedThumbnail() async {
    final cachedThumbnail = await _cacheService.getThumbnail(_videoData.id);
    if (cachedThumbnail != null && mounted) {
      setState(() {
        _videoData = _videoData.copyWith(thumbnailUrl: cachedThumbnail);
      });
    }
  }

  Future<void> _initializeConnection() async {
    try {
      await _websocketService.connect();
      if (mounted) {
        setState(() {
          _isConnected = true;
          _captionFuture = _generateCaption();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to server: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeConnection,
            ),
          ),
        );
      }
    }
  }

  Future<String> _generateCaption() async {
    if (!_isConnected) {
      return 'Error: Not connected to server';
    }
    
    try {
      return await _websocketService.generateCaption(
        _videoData.title,
        _videoData.description,
      );
    } catch (e) {
      return 'Error generating caption: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 900;
        
        return Scaffold(
          appBar: AppBar(
            title: Text(_videoData.title),
            actions: [
              IconButton(
                icon: Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                onPressed: _isConnected ? null : _initializeConnection,
              ),
            ],
          ),
          body: SafeArea(
            child: isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMainContent(),
                      ),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: ChatWidget(videoId: widget.video.id),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildMainContent(),
                      const SizedBox(height: 16),
                      // Modified this part
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ChatWidget(
                            videoId: widget.video.id,
                            isCompact: true,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video Player
          VideoPlayerWidget(
            video: _videoData,
            initialThumbnailUrl: _videoData.thumbnailUrl,
            autoPlay: true,
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            _videoData.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AiTubeColors.onBackground,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Tags
          if (_videoData.tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _videoData.tags.map((tag) => Chip(
                label: Text(tag),
                backgroundColor: AiTubeColors.surface,
                labelStyle: const TextStyle(color: AiTubeColors.onSurface),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Description Section
          const Text(
            'Description',
            style: TextStyle(
              color: AiTubeColors.onBackground,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _videoData.description,
            style: const TextStyle(
              color: AiTubeColors.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Cancel any pending video-related requests
    _websocketService.cancelRequestsForVideo(widget.video.id);
    _websocketService.removeSubscriber(widget.video.id);
    
    // Cleanup other resources
    super.dispose();
  }

}