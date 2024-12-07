// lib/models/chat_message.dart
import 'package:uuid/uuid.dart';

class ChatMessage {
  final String id;
  final String userId;
  final String username;
  final String content;
  final DateTime timestamp;
  final String videoId;
  final String? color;

  ChatMessage({
    String? id,
    required this.userId,
    required this.username,
    required this.content,
    required this.videoId,
    this.color,
    DateTime? timestamp,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Handle potential null or missing values
    final String? id = json['id'] as String?;
    final String? userId = json['userId'] as String?;
    final String? username = json['username'] as String?;
    final String? content = json['content'] as String?;
    final String? videoId = json['videoId'] as String?;
    final String? color = json['color'] as String?;
    
    // Validate required fields
    if (userId == null || username == null || content == null || videoId == null) {
      throw FormatException(
        'Invalid chat message format. Required fields missing: ${[
          if (userId == null) 'userId',
          if (username == null) 'username',
          if (content == null) 'content',
          if (videoId == null) 'videoId',
        ].join(', ')}'
      );
    }

    // Parse timestamp with fallback
    DateTime? timestamp;
    final timestampStr = json['timestamp'] as String?;
    if (timestampStr != null) {
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (e) {
        print('Error parsing timestamp: $e');
        // Use current time as fallback
        timestamp = DateTime.now();
      }
    }

    return ChatMessage(
      id: id,
      userId: userId,
      username: username,
      content: content,
      videoId: videoId,
      color: color,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'username': username,
    'content': content,
    'videoId': videoId,
    'color': color,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  String toString() => 'ChatMessage(id: $id, userId: $userId, username: $username, content: $content, videoId: $videoId)';
}