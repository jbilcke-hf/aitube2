// lib/services/cache_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as prefs;
import 'package:idb_shim/idb_browser.dart' if (dart.library.io) 'package:idb_shim/idb_io.dart';
import '../models/video_result.dart';

/// Storage provider to handle platform differences
abstract class StorageProvider {
  Future<void> initialize();
  Future<void> write(String key, Uint8List data);
  Future<Uint8List?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();
  Future<int> getTotalSize();
}

/// IndexedDB implementation for web platform
class WebStorageProvider implements StorageProvider {
  late Database _db;
  static const String _storeName = 'binary_store';
  
  @override
  Future<void> initialize() async {
    final factory = getIdbFactory()!;
    _db = await factory.open(
      'aitube_cache',
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final db = event.database;
        db.createObjectStore(_storeName);
      },
    );
  }

  @override
  Future<void> write(String key, Uint8List data) async {
    final txn = _db.transaction(_storeName, 'readwrite');
    final store = txn.objectStore(_storeName);
    await store.put(data, key);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final txn = _db.transaction(_storeName, 'readonly');
    final store = txn.objectStore(_storeName);
    final data = await store.getObject(key);
    if (data == null) return null;
    return data as Uint8List;
  }

  @override
  Future<void> delete(String key) async {
    final txn = _db.transaction(_storeName, 'readwrite');
    final store = txn.objectStore(_storeName);
    await store.delete(key);
  }

  @override
  Future<void> clear() async {
    final txn = _db.transaction(_storeName, 'readwrite');
    final store = txn.objectStore(_storeName);
    await store.clear();
  }

  @override
  Future<int> getTotalSize() async {
    final txn = _db.transaction(_storeName, 'readonly');
    final store = txn.objectStore(_storeName);
    final keys = await store.getAllKeys();
    int totalSize = 0;
    
    for (final key in keys) {
      final data = await store.getObject(key);
      if (data is Uint8List) {
        totalSize += data.length;
      }
    }
    
    return totalSize;
  }
}

/// Memory-based implementation for web platform
class MemoryStorageProvider implements StorageProvider {
  final Map<String, Uint8List> _storage = {};
  
  @override
  Future<void> initialize() async {}

  @override
  Future<void> write(String key, Uint8List data) async {
    _storage[key] = data;
  }

  @override
  Future<Uint8List?> read(String key) async {
    return _storage[key];
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }

  @override
  Future<int> getTotalSize() async {
    return _storage.values.fold<int>(0, (total, data) => total + data.length);
  }
}

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;

  late final prefs.SharedPreferences _prefs;
  late final StorageProvider _storage;
  final _statsController = StreamController<CacheStats>.broadcast();
  
  static const String _metadataPrefix = 'metadata_';
  static const String _videoPrefix = 'video_';
  static const String _thumbnailPrefix = 'thumb_';
  static const Duration _cacheExpiry = Duration(days: 7);

  Stream<CacheStats> get statsStream => _statsController.stream;

  CacheService._internal() {
    // Use IndexedDB for web, memory storage for testing/development
    _storage = kIsWeb ? WebStorageProvider() : MemoryStorageProvider();
  }

  Future<void> initialize() async {
    await _storage.initialize();
    _prefs = await prefs.SharedPreferences.getInstance();
    await _cleanExpiredEntries();
    await _updateStats();
  }

  Future<void> _cleanExpiredEntries() async {
    final now = DateTime.now();
    final keys = _prefs.getKeys().where((k) => k.startsWith(_metadataPrefix));
    
    for (final key in keys) {
      final metadata = _prefs.getString(key);
      if (metadata != null) {
        final data = json.decode(metadata);
        final timestamp = DateTime.parse(data['timestamp']);
        if (now.difference(timestamp) > _cacheExpiry) {
          await _removeEntry(key.substring(_metadataPrefix.length));
        }
      }
    }
  }

  Future<void> _removeEntry(String key) async {
    await _prefs.remove('$_metadataPrefix$key');
    await _storage.delete(key);
    await _updateStats();
  }

  Future<void> _updateStats() async {
    final totalSize = await _storage.getTotalSize();
    final totalItems = _prefs.getKeys()
        .where((k) => k.startsWith(_metadataPrefix))
        .length;
    
    _statsController.add(CacheStats(
      totalItems: totalItems,
      totalSizeMB: totalSize / (1024 * 1024),
    ));
  }

  Future<void> cacheSearchResults(String query, List<VideoResult> results) async {
    final key = 'search_$query';
    final data = Uint8List.fromList(utf8.encode(json.encode({
      'query': query,
      'results': results.map((r) => r.toJson()).toList(),
    })));

    await _storage.write(key, data);
    await _prefs.setString('$_metadataPrefix$key', json.encode({
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'search',
    }));

    await _updateStats();
  }

  Future<List<VideoResult>?> getSearchResults(String query) async {
    final key = 'search_$query';
    final data = await _storage.read(key);
    if (data == null) return null;

    final decoded = json.decode(utf8.decode(data));
    return (decoded['results'] as List)
        .map((r) => VideoResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> cacheVideoData(String videoId, String videoData) async {
    final key = '$_videoPrefix$videoId';
    final data = _extractVideoData(videoData);
    
    await _storage.write(key, data);
    await _prefs.setString('$_metadataPrefix$key', json.encode({
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'video',
    }));

    await _updateStats();
  }

  Future<String?> getVideoData(String videoId) async {
    final key = '$_videoPrefix$videoId';
    final data = await _storage.read(key);
    if (data == null) return null;

    return 'data:video/mp4;base64,${base64Encode(data)}';
  }

  Future<void> cacheThumbnail(String videoId, String thumbnailData) async {
    final key = '$_thumbnailPrefix$videoId';
    final data = _extractImageData(thumbnailData);
    
    await _storage.write(key, data);
    await _prefs.setString('$_metadataPrefix$key', json.encode({
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'thumbnail',
    }));

    await _updateStats();
  }

  Future<String?> getThumbnail(String videoId) async {
    final key = '$_thumbnailPrefix$videoId';
    final data = await _storage.read(key);
    if (data == null) return null;

    return 'data:image/jpeg;base64,${base64Encode(data)}';
  }

  Uint8List _extractVideoData(String videoData) {
    final parts = videoData.split(',');
    if (parts.length != 2) throw Exception('Invalid video data format');
    return base64Decode(parts[1]);
  }

  Uint8List _extractImageData(String imageData) {
    final parts = imageData.split(',');
    if (parts.length != 2) throw Exception('Invalid image data format');
    return base64Decode(parts[1]);
  }

  Future<void> delete(String key) async {
    await _storage.delete('${_videoPrefix}$key');
    await _prefs.remove('$_metadataPrefix${_videoPrefix}$key');
    await _updateStats();
  }

  Future<void> clearCache() async {
    await _storage.clear();
    final keys = _prefs.getKeys().where((k) => k.startsWith(_metadataPrefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
    await _updateStats();
  }
  
  Future<void> cacheSearchResult(String query, VideoResult result, int searchCount) async {
    final key = 'search_${query}_$searchCount';
    final data = Uint8List.fromList(utf8.encode(json.encode({
      'query': query,
      'searchCount': searchCount,
      'result': result.toJson(),
    })));

    await _storage.write(key, data);
    await _prefs.setString('$_metadataPrefix$key', json.encode({
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'search',
    }));

    await _updateStats();
  }

  Future<List<VideoResult>> getCachedSearchResults(String query) async {
    final results = <VideoResult>[];
    final searchKeys = _prefs.getKeys()
        .where((k) => k.startsWith('${_metadataPrefix}search_$query'));
    
    for (final key in searchKeys) {
      final data = await _storage.read(key.substring(_metadataPrefix.length));
      if (data != null) {
        final decoded = json.decode(utf8.decode(data));
        results.add(VideoResult.fromJson(decoded['result'] as Map<String, dynamic>));
      }
    }

    return results..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> getLastSearchCount(String query) async {
    final searchKeys = _prefs.getKeys()
        .where((k) => k.startsWith('${_metadataPrefix}search_$query'))
        .toList();
    
    if (searchKeys.isEmpty) return 0;
    
    int maxCount = -1;
    for (final key in searchKeys) {
      final match = RegExp(r'search_.*_(\d+)$').firstMatch(key);
      if (match != null) {
        final count = int.parse(match.group(1)!);
        if (count > maxCount) maxCount = count;
      }
    }
    
    return maxCount + 1;
  }

  void dispose() {
    _statsController.close();
  }
}

class CacheStats {
  final int totalItems;
  final double totalSizeMB;

  CacheStats({
    required this.totalItems,
    required this.totalSizeMB,
  });
}