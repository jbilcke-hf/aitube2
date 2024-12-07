
// lib/services/chat_service.dart
import 'dart:async';
import 'dart:math';
import 'package:aitube2/services/websocket_api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';

class ChatService {
 static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  static const _userIdKey = 'chat_user_id';
  static const _usernameKey = 'chat_username';
  static const _userColorKey = 'chat_user_color';
  
  final _chatController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get chatStream => _chatController.stream;
  
  final WebSocketApiService _websocketService = WebSocketApiService();
  String? _userId;
  String? _username;
  String? _userColor;
  String? _currentRoomId;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_userIdKey);
    _username = prefs.getString(_usernameKey);
    _userColor = prefs.getString(_userColorKey);

    if (_userId == null) {
      _userId = const Uuid().v4();
      _username = 'User${_userId!.substring(0, 4)}';
      _userColor = _generateRandomColor();
      
      await prefs.setString(_userIdKey, _userId!);
      await prefs.setString(_usernameKey, _username!);
      await prefs.setString(_userColorKey, _userColor!);
    }

    // Set up message handling before attempting to join
    _websocketService.chatStream.listen(_handleChatMessage);
    _isInitialized = true;
  }

  Future<void> joinRoom(String videoId) async {
    if (_currentRoomId == videoId) return; // Already in this room
    
    try {
      // Leave current room if in one
      if (_currentRoomId != null) {
        await leaveRoom(_currentRoomId!);
      }

      // Initialize if needed
      if (!_isInitialized) {
        await initialize();
      }

      await _websocketService.joinChatRoom(videoId);
      _currentRoomId = videoId;
      debugPrint('Successfully joined chat room for video: $videoId');
    } catch (e) {
      debugPrint('Error joining chat room: $e');
      rethrow;
    }
  }

  Future<void> leaveRoom(String videoId) async {
    if (_currentRoomId == videoId && _websocketService.isConnected) {
      await _websocketService.leaveChatRoom(videoId);
      _currentRoomId = null;
      debugPrint('Left chat room for video: $videoId');
    }
  }

  String _generateRandomColor() {
    final colors = [
      '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
      '#FFEEAD', '#D4A5A5', '#9B9B9B', '#A8E6CF'
    ];
    return colors[Random().nextInt(colors.length)];
  }

  Future<bool> sendMessage(String content, String videoId) async {
    if (content.trim().isEmpty) return false;
    if (content.length > 256) {
      content = content.substring(0, 256);
    }

    try {
      debugPrint('ChatService: Attempting to send message to room $videoId');
      
      if (_currentRoomId != videoId) {
        debugPrint('ChatService: Not in correct room, joining...');
        await joinRoom(videoId);
      }

      if (!_websocketService.isConnected) {
        debugPrint('ChatService: WebSocket not connected, attempting to connect...');
        await _websocketService.connect();
      }

      final message = ChatMessage(
        userId: _userId!,
        username: _username!,
        content: content,
        videoId: videoId,
        color: _userColor,
      );

      debugPrint('ChatService: Sending message via WebSocket...');
      await _websocketService.sendChatMessage(message);
      debugPrint('ChatService: Message sent successfully');
      return true;
      
    } catch (e) {
      debugPrint('ChatService: Error sending message: $e');
      if (e is TimeoutException) {
        // Try to reconnect on timeout
        debugPrint('ChatService: Timeout occurred, attempting to reconnect...');
        try {
          await _websocketService.connect();
          debugPrint('ChatService: Reconnected, retrying message send...');
          return sendMessage(content, videoId); // Retry once
        } catch (reconnectError) {
          debugPrint('ChatService: Reconnection failed: $reconnectError');
        }
      }
      return false;
    }
  }

  void _handleChatMessage(ChatMessage message) {
    // Only add messages if they're for the current room
    if (message.videoId == _currentRoomId) {
      _chatController.add(message);
      debugPrint('Received chat message: ${message.id} from ${message.username}');
    }
  }

  void dispose() {
    if (_currentRoomId != null) {
      leaveRoom(_currentRoomId!);
    }
    _chatController.close();
    _isInitialized = false;
  }
}
