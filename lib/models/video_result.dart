import 'package:uuid/uuid.dart';

class VideoResult {
  final String id;
  final String title;
  final List<String> tags;
  final String description;
  final String thumbnailUrl;
  final String caption;
  final bool isLatent;

  // this is a trick we use for some simulations
  // it works well for webcams scenarios where
  // we want geometry consistency
  final bool useFixedSeed;
  final int seed;

  final int views;
  final String createdAt;

  VideoResult({
    String? id,
    required this.title,
    this.tags = const [],
    this.description = '',
    this.thumbnailUrl = '',
    this.caption = '',
    this.isLatent = true,
    this.useFixedSeed = false,
    this.seed = 0,
    this.views = 0,
    String? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory VideoResult.fromJson(Map<String, dynamic> json) {
    return VideoResult(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Untitled',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      isLatent: json['isLatent'] as bool? ?? true,
      useFixedSeed: json['useFixedSeed'] as bool? ?? false,
      seed: json['seed'] as int? ?? 0,
      views: json['views'] as int? ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'tags': tags,
    'description': description, 
    'thumbnailUrl': thumbnailUrl,
    'caption': caption,
    'isLatent': isLatent,
    'useFixedSeed': useFixedSeed,
    'seed': seed,
    'views': views,
    'createdAt': createdAt,
  };

  /// Create a copy of this VideoResult with the given fields replaced with new values
  VideoResult copyWith({
    String? id,
    String? title,
    List<String>? tags,
    String? description,
    String? thumbnailUrl,
    String? caption,
    bool? isLatent,
    bool? useFixedSeed,
    int? seed,
    int? views,
    String? createdAt,
  }) {
    return VideoResult(
      id: id ?? this.id,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl, 
      caption: caption ?? this.caption,
      isLatent: isLatent ?? this.isLatent,
      useFixedSeed: useFixedSeed ?? this.useFixedSeed,
      seed: seed ?? this.seed,
      views: views ?? this.views,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}