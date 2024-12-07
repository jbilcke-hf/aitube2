// lib/formats/openclap.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

enum ClapFormat {
  clap0('clap-0'),
  clap0b('clap-0b');

  final String value;
  const ClapFormat(this.value);

  static ClapFormat fromString(String value) {
    return ClapFormat.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ClapFormat.clap0,
    );
  }
}

enum ClapSegmentCategory {
  splat('SPLAT'),
  mesh('MESH'),
  depth('DEPTH'),
  effect('EFFECT'),
  event('EVENT'),
  interface('INTERFACE'),
  phenomenon('PHENOMENON'),
  video('VIDEO'),
  image('IMAGE'),
  transition('TRANSITION'),
  character('CHARACTER'),
  location('LOCATION'),
  time('TIME'),
  era('ERA'),
  lighting('LIGHTING'),
  weather('WEATHER'),
  action('ACTION'),
  music('MUSIC'),
  sound('SOUND'),
  dialogue('DIALOGUE'),
  style('STYLE'),
  camera('CAMERA'),
  group('GROUP'),
  generic('GENERIC');

  final String value;
  const ClapSegmentCategory(this.value);

  // Updated to handle nullable String input
  static ClapSegmentCategory fromString(String? value) {
    if (value == null) return ClapSegmentCategory.generic;
    
    return ClapSegmentCategory.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => ClapSegmentCategory.generic,
    );
  }
}

enum ClapImageRatio {
  landscape('LANDSCAPE'),
  portrait('PORTRAIT'),
  square('SQUARE');

  final String value;
  const ClapImageRatio(this.value);

  static ClapImageRatio fromString(String? value) {
    if (value == null) return ClapImageRatio.landscape;
    return ClapImageRatio.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => ClapImageRatio.landscape,
    );
  }
}

enum ClapOutputType {
  text('TEXT'),
  animation('ANIMATION'),
  interface('INTERFACE'),
  event('EVENT'),
  phenomenon('PHENOMENON'),
  transition('TRANSITION'),
  image('IMAGE'),
  imageSegmentation('IMAGE_SEGMENTATION'),
  imageDepth('IMAGE_DEPTH'),
  video('VIDEO'),
  videoSegmentation('VIDEO_SEGMENTATION'),
  videoDepth('VIDEO_DEPTH'),
  audio('AUDIO');

  final String value;
  const ClapOutputType(this.value);

  static ClapOutputType fromString(String? value) {
    if (value == null) return ClapOutputType.text;
    return ClapOutputType.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => ClapOutputType.text,
    );
  }
}

enum ClapAssetSource {
  remote('REMOTE'),
  path('PATH'),
  data('DATA'),
  prompt('PROMPT'),
  empty('EMPTY');

  final String value;
  const ClapAssetSource(this.value);

  static ClapAssetSource fromString(String? value) {
    if (value == null) return ClapAssetSource.empty;
    return ClapAssetSource.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => ClapAssetSource.empty,
    );
  }
}

/// Data classes for CLAP structure

class ClapMeta {
  final String id;
  final String title;
  final String description;
  final String caption;
  final String licence;
  final int bpm;
  final double frameRate;
  final List<String> tags;
  final String thumbnailUrl;
  final ClapImageRatio imageRatio;
  final int durationInMs;
  final int width;
  final int height;
  final String imagePrompt;
  final String systemPrompt;
  final String storyPrompt;
  final bool isLoop;
  final bool isInteractive;

  ClapMeta({
    String? id,
    this.title = '',
    this.description = '',
    this.caption = '',
    this.licence = '',
    this.bpm = 120,
    this.frameRate = 24,
    this.tags = const [],
    this.thumbnailUrl = '',
    ClapImageRatio? imageRatio,
    this.durationInMs = 4000,
    this.width = 1024,
    this.height = 576,
    this.imagePrompt = '',
    this.systemPrompt = '',
    this.storyPrompt = '',
    this.isLoop = false,
    this.isInteractive = false,
  }) : id = id ?? const Uuid().v4(),
       imageRatio = imageRatio ?? ClapImageRatio.landscape;

  factory ClapMeta.fromMap(Map<String, dynamic> map) {
    return ClapMeta(
      id: map['id'] as String?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      caption: map['caption'] as String? ?? '',
      licence: map['licence'] as String? ?? '',
      bpm: (map['bpm'] as num?)?.toInt() ?? 120,
      frameRate: (map['frameRate'] as num?)?.toDouble() ?? 24,
      tags: List<String>.from(map['tags'] ?? []),
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      imageRatio: ClapImageRatio.fromString(map['imageRatio'] as String?),
      durationInMs: (map['durationInMs'] as num?)?.toInt() ?? 4000,
      width: (map['width'] as num?)?.toInt() ?? 1024,
      height: (map['height'] as num?)?.toInt() ?? 576,
      imagePrompt: map['imagePrompt'] as String? ?? '',
      systemPrompt: map['systemPrompt'] as String? ?? '',
      storyPrompt: map['storyPrompt'] as String? ?? '',
      isLoop: map['isLoop'] as bool? ?? false,
      isInteractive: map['isInteractive'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'caption': caption,
      'licence': licence,
      'bpm': bpm,
      'frameRate': frameRate,
      'tags': tags,
      'thumbnailUrl': thumbnailUrl,
      'imageRatio': imageRatio.value,
      'durationInMs': durationInMs,
      'width': width,
      'height': height,
      'imagePrompt': imagePrompt,
      'systemPrompt': systemPrompt,
      'storyPrompt': storyPrompt,
      'isLoop': isLoop,
      'isInteractive': isInteractive,
    };
  }
}

class ClapSegment {
  final String id;
  final String parentId;
  final List<String> childrenIds;
  final int track;
  final int startTimeInMs;
  final int endTimeInMs;
  final ClapSegmentCategory category;
  final String entityId;
  final String workflowId;
  final String sceneId;
  final int startTimeInLines;
  final int endTimeInLines;
  final String prompt;
  final String label;
  final ClapOutputType outputType;
  final String renderId;
  final String status;
  final String assetUrl;
  final int assetDurationInMs;
  final ClapAssetSource assetSourceType;
  final String assetFileFormat;
  final String createdAt;
  final String createdBy;
  final int revision;
  final String editedBy;
  final double outputGain;
  final int seed;

  ClapSegment({
    String? id,
    this.parentId = '',
    this.childrenIds = const [],
    this.track = 0,
    this.startTimeInMs = 0,
    this.endTimeInMs = 0,
    ClapSegmentCategory? category,
    this.entityId = '',
    this.workflowId = '',
    this.sceneId = '',
    this.startTimeInLines = 0,
    this.endTimeInLines = 0,
    this.prompt = '',
    this.label = '',
    ClapOutputType? outputType,
    this.renderId = '',
    this.status = 'TO_GENERATE',
    this.assetUrl = '',
    this.assetDurationInMs = 0,
    ClapAssetSource? assetSourceType,
    this.assetFileFormat = '',
    String? createdAt,
    this.createdBy = 'ai',
    this.revision = 0,
    this.editedBy = 'ai',
    this.outputGain = 0,
    int? seed,
  }) : id = id ?? const Uuid().v4(),
       category = category ?? ClapSegmentCategory.generic,
       outputType = outputType ?? ClapOutputType.text,
       assetSourceType = assetSourceType ?? ClapAssetSource.empty,
       createdAt = createdAt ?? DateTime.now().toIso8601String(),
       seed = seed ?? Random().nextInt(1 << 31);

  factory ClapSegment.fromMap(Map<String, dynamic> map) {
    return ClapSegment(
      id: map['id'] as String?,
      parentId: map['parentId'] as String? ?? '',
      childrenIds: List<String>.from(map['childrenIds'] ?? []),
      track: (map['track'] as num?)?.toInt() ?? 0,
      startTimeInMs: (map['startTimeInMs'] as num?)?.toInt() ?? 0,
      endTimeInMs: (map['endTimeInMs'] as num?)?.toInt() ?? 0,
      category: ClapSegmentCategory.fromString(map['category'] as String?),
      entityId: map['entityId'] as String? ?? '',
      workflowId: map['workflowId'] as String? ?? '',
      sceneId: map['sceneId'] as String? ?? '',
      startTimeInLines: (map['startTimeInLines'] as num?)?.toInt() ?? 0,
      endTimeInLines: (map['endTimeInLines'] as num?)?.toInt() ?? 0,
      prompt: map['prompt'] as String? ?? '',
      label: map['label'] as String? ?? '',
      outputType: ClapOutputType.fromString(map['outputType'] as String?),
      renderId: map['renderId'] as String? ?? '',
      status: map['status'] as String? ?? 'TO_GENERATE',
      assetUrl: map['assetUrl'] as String? ?? '',
      assetDurationInMs: (map['assetDurationInMs'] as num?)?.toInt() ?? 0,
      assetSourceType: ClapAssetSource.fromString(map['assetSourceType'] as String?),
      assetFileFormat: map['assetFileFormat'] as String? ?? '',
      createdAt: map['createdAt'] as String?,
      createdBy: map['createdBy'] as String? ?? 'ai',
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      editedBy: map['editedBy'] as String? ?? 'ai',
      outputGain: (map['outputGain'] as num?)?.toDouble() ?? 0,
      seed: (map['seed'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'parentId': parentId,
      'childrenIds': childrenIds,
      'track': track,
      'startTimeInMs': startTimeInMs,
      'endTimeInMs': endTimeInMs,
      'category': category.value,
      'entityId': entityId,
      'workflowId': workflowId,
      'sceneId': sceneId,
      'startTimeInLines': startTimeInLines,
      'endTimeInLines': endTimeInLines,
      'prompt': prompt,
      'label': label,
      'outputType': outputType.value,
      'renderId': renderId,
      'status': status,
      'assetUrl': assetUrl,
      'assetDurationInMs': assetDurationInMs,
      'assetSourceType': assetSourceType.value,
      'assetFileFormat': assetFileFormat,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'revision': revision,
      'editedBy': editedBy,
      'outputGain': outputGain,
      'seed': seed,
    };
  }
}

/// Main CLAP parser class

class ClapParser {
  static Future<Map<String, dynamic>> parseClap(dynamic source, {
    bool debug = false,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0, 'Opening .clap file...');

    // Handle different input types
    String yamlString;
    if (source is String) {
      if (source.startsWith('data:application/x-gzip;base64,') ||
          source.startsWith('data:application/octet-stream;base64,')) {
        // Handle base64 data URI
        yamlString = await _decompressBase64(source);
      } else if (source.startsWith('http://') || source.startsWith('https://')) {
        // Handle remote URL
        onProgress?.call(0.2, 'Downloading .clap file...');
        final response = await http.get(Uri.parse(source));
        if (response.statusCode != 200) {
          throw Exception('Failed to download the .clap file');
        }
        yamlString = await _decompressBytes(response.bodyBytes);
      } else {
        // Assume direct YAML string
        yamlString = source;
      }
    } else if (source is Uint8List) {
      // Handle compressed bytes
      yamlString = await _decompressBytes(source);
    } else {
      throw Exception('Unsupported source type');
    }

    onProgress?.call(0.4, 'Parsing .clap file...');

    // Parse YAML
    final yaml = loadYaml(yamlString) as YamlList;
    if (yaml.length < 2) {
      throw Exception('Invalid CLAP file: missing header or metadata');
    }

    // Validate format
    final header = yaml[0] as YamlMap;
    if (header['format'] != ClapFormat.clap0.value) {
      throw Exception('Invalid CLAP format');
    }

    onProgress?.call(0.6, 'Processing metadata...');

    // Parse metadata
    final meta = ClapMeta.fromMap(_yamlToMap(yaml[1] as YamlMap));

    // Parse segments and other components
    final segments = <ClapSegment>[];
    final expectedSegments = (header['numberOfSegments'] as int?) ?? 0;
    
    onProgress?.call(0.8, 'Processing segments...');

    for (int i = 2; i < yaml.length && i < (2 + expectedSegments); i++) {
      segments.add(ClapSegment.fromMap(_yamlToMap(yaml[i] as YamlMap)));
    }

    onProgress?.call(1.0, 'Completed parsing');

    return {
      'meta': meta,
      'segments': segments,
      // Add other components as needed
    };
  }

  /// Helper method to decompress base64 data URI
  static Future<String> _decompressBase64(String dataUri) async {
    final base64Data = dataUri.split(',')[1];
    final bytes = base64Decode(base64Data);
    return _decompressBytes(bytes);
  }

  /// Helper method to decompress gzipped bytes
  static Future<String> _decompressBytes(Uint8List bytes) async {
    try {
      final decompressed = GZipCodec().decode(bytes);
      return utf8.decode(decompressed);
    } catch (e) {
      throw Exception('Failed to decompress CLAP file: $e');
    }
  }

  /// Helper method to convert YamlMap to regular Map
  static Map<String, dynamic> _yamlToMap(YamlMap yaml) {
    return Map<String, dynamic>.from(yaml);
  }
}

/// CLAP Serializer class for creating CLAP files

class ClapSerializer {
  static Future<Uint8List> serializeClap(Map<String, dynamic> clap) async {
    final meta = clap['meta'] as ClapMeta;
    final segments = (clap['segments'] as List<ClapSegment>?)?.toList() ?? [];

    // Create header
    final header = {
      'format': ClapFormat.clap0.value,
      'numberOfSegments': segments.length,
      // Add other counts as needed
    };

    // Create YAML entries
    final entries = [
      header,
      meta.toMap(),
      ...segments.map((s) => s.toMap()),
    ];

    // Convert to YAML string
    final yaml = toYamlString(entries);

    // Compress
    final compressed = GZipCodec().encode(utf8.encode(yaml));
    return Uint8List.fromList(compressed);
  }

  /// Helper method to convert data to YAML string
  static String toYamlString(List<Map<String, dynamic>> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln('---');
      _writeYamlMap(entry, buffer);
    }
    return buffer.toString();
  }

  /// Helper method to write map as YAML
  static void _writeYamlMap(Map<String, dynamic> map, StringBuffer buffer, [String indent = '']) {
    for (final entry in map.entries) {
      if (entry.value == null) continue;
      
      if (entry.value is Map) {
        buffer.writeln('$indent${entry.key}:');
        _writeYamlMap(entry.value as Map<String, dynamic>, buffer, '$indent  ');
      } else if (entry.value is List) {
        if ((entry.value as List).isEmpty) {
          buffer.writeln('$indent${entry.key}: []');
        } else {
          buffer.writeln('$indent${entry.key}:');
          for (final item in entry.value as List) {
            if (item is Map) {
              buffer.writeln('$indent  -');
              _writeYamlMap(item as Map<String, dynamic>, buffer, '$indent    ');
            } else {
              buffer.writeln('$indent  - $item');
            }
          }
        }
      } else {
        buffer.writeln('$indent${entry.key}: ${_formatYamlValue(entry.value)}');
      }
    }
  }

  /// Helper method to format YAML values
  static String _formatYamlValue(dynamic value) {
    if (value is String) {
      if (value.contains('\n') || value.contains(':') || value.contains('#')) {
        return '|\n    ${value.replaceAll('\n', '\n    ')}';
      }
      return value.contains(' ') ? '"$value"' : value;
    }
    return value.toString();
  }
}

/// Example usage class

class ClapFile {
  static Future<ClapFile> fromSource(dynamic source) async {
    final parsed = await ClapParser.parseClap(source);
    return ClapFile._(parsed);
  }

  final ClapMeta meta;
  final List<ClapSegment> segments;
  // Add other components as needed

  ClapFile._(Map<String, dynamic> parsed)
      : meta = parsed['meta'] as ClapMeta,
        segments = (parsed['segments'] as List<ClapSegment>?)?.toList() ?? [];

  Future<Uint8List> serialize() async {
    return ClapSerializer.serializeClap({
      'meta': meta,
      'segments': segments,
    });
  }

  /// Helper method to save to a file
  Future<void> saveToFile(String path) async {
    final bytes = await serialize();
    await File(path).writeAsBytes(bytes);
  }

  /// Helper method to create a data URI
  Future<String> toDataUri() async {
    final bytes = await serialize();
    final base64 = base64Encode(bytes);
    return 'data:application/x-gzip;base64,$base64';
  }
}