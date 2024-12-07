import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../models/video_result.dart';

class VideoCard extends StatelessWidget {
  final VideoResult video;

  const VideoCard({
    super.key,
    required this.video,
  });

  Widget _buildThumbnail() {
    if (video.thumbnailUrl.isEmpty) {
      return Container(
        color: AiTubeColors.surfaceVariant,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.movie_creation,
                color: AiTubeColors.onSurfaceVariant,
                size: 32,
              ),
              SizedBox(height: 8),
              Text(
                'Generating preview...',
                style: TextStyle(
                  color: AiTubeColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    try {
      if (video.thumbnailUrl.startsWith('data:image')) {
        final uri = Uri.parse(video.thumbnailUrl);
        final base64Data = uri.data?.contentAsBytes();
        
        if (base64Data == null) {
          throw Exception('Invalid image data');
        }

        return Image.memory(
          base64Data,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorThumbnail();
          },
        );
      }

      return Image.network(
        video.thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorThumbnail();
        },
      );
    } catch (e) {
      return _buildErrorThumbnail();
    }
  }

  Widget _buildErrorThumbnail() {
    return Container(
      color: AiTubeColors.surfaceVariant,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image,
              color: AiTubeColors.onSurfaceVariant,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              'Preview unavailable',
              style: TextStyle(
                color: AiTubeColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(),
                if (video.isLatent) 
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.ac_unit,
                            size: 16,
                            color: AiTubeColors.onBackground,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Latent',
                            style: TextStyle(
                              color: AiTubeColors.onBackground,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: AiTubeColors.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AiTubeColors.surfaceVariant,
                  child: Icon(
                    Icons.play_arrow,
                    color: AiTubeColors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          color: AiTubeColors.onBackground,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Generated using LTX Video',
                        style: const TextStyle(
                          color: AiTubeColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}