import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class Configuration {
  static Configuration? _instance;
  static Configuration get instance => _instance ??= Configuration._();

  late Map<String, dynamic> _config;
  
  // Prevent multiple instances
  Configuration._();

  static const String _defaultConfigPath = 'assets/config/default.yaml';
  
  Future<void> initialize() async {
    // Load default config first
    final defaultYaml = await rootBundle.loadString(_defaultConfigPath);
    _config = _convertYamlToMap(loadYaml(defaultYaml));

    // Get custom config path from environment
    const customConfigPath = String.fromEnvironment(
      'CONFIG_PATH',
      defaultValue: 'assets/config/aitube.yaml'
    );

    try {
      // Load and merge custom config
      final customYaml = await rootBundle.loadString(customConfigPath);
      final customConfig = _convertYamlToMap(loadYaml(customYaml));
      _mergeConfig(customConfig);
    } catch (e) {
      print('Warning: Could not load custom config from $customConfigPath: $e');
    }
  }

  Map<String, dynamic> _convertYamlToMap(YamlMap yamlMap) {
    Map<String, dynamic> result = {};
    for (var entry in yamlMap.entries) {
      if (entry.value is YamlMap) {
        result[entry.key.toString()] = _convertYamlToMap(entry.value);
      } else {
        result[entry.key.toString()] = entry.value;
      }
    }
    return result;
  }

  void _mergeConfig(Map<String, dynamic> customConfig) {
    for (var entry in customConfig.entries) {
      if (entry.value is Map<String, dynamic> && 
          _config[entry.key] is Map<String, dynamic>) {
        _config[entry.key] = {
          ..._config[entry.key] as Map<String, dynamic>,
          ...entry.value as Map<String, dynamic>
        };
      } else {
        _config[entry.key] = entry.value;
      }
    }
  }

  // Getters for configuration values

  String get uiProductName => 
      _config['ui']['product_name'];

  // how many clips should be stored in advance
  int get renderQueueBufferSize => 
      _config['render_queue']['buffer_size'];

  // how many requests for clips can be run in parallel
  int get renderQueueMaxConcurrentGenerations => 
      _config['render_queue']['max_concurrent_generations'];

  // start playback as soon as we have a certain number of videoclips in memory (eg 25%)
  int get minimumBufferPercentToStartPlayback => 
      _config['render_queue']['minimum_buffer_percent_to_start_playback'];

  // transition time between each clip
  // the exit (older) clip will see its playback time reduced by this amount
  Duration get transitionBufferDuration => 
      Duration(milliseconds: _config['video']['transition_buffer_duration_ms']);

  // how long a generated clip should be, in Duration
  Duration get originalClipDuration => 
      Duration(seconds: _config['video']['original_clip_duration_seconds']);

  // The model works on resolutions that are divisible by 32
  // and number of frames that are divisible by 8 + 1 (e.g. 257).
  // 
  // In case the resolution or number of frames are not divisible
  // by 32 or 8 + 1, the input will be padded with -1 and then
  // cropped to the desired resolution and number of frames.
  // 
  // The model works best on resolutions under 720 x 1280 and
  // number of frames below 257.

  // number of inference steps
  // this has a direct impact in performance obviously,
  // you can try to go to low values like 12 or 14 on "safe bet" prompts,
  // but if you need a more uncommon topic, you need to go to 18 steps or more
  int get numInferenceSteps => 
      _config['video']['num_inference_steps'];


  // original frame-rate of each clip (before we slow them down)
  // in frames per second (so an integer)
  int get originalClipFrameRate => 
      _config['video']['original_clip_frame_rate'];

  int get originalClipWidth => 
      _config['video']['original_clip_width'];

  int get originalClipHeight => 
      _config['video']['original_clip_height'];

  // to do more with less, we can slow down the videos (a 3s video will become a 4s video)
  // but if you are GPU rich feel feel to play them back at 100% of their speed!
  double get clipPlaybackSpeed => 
      _config['video']['clip_playback_speed'].toDouble();

  // Computed properties

  // original frame-rate of each clip (before we slow them down)
  // in frames (so an integer)
  // ----------------------- IMPORTANT --------------------------
  // the model has to use a number of frames that can be divided by 8
  // so originalClipNumberOfFrames might not be the actual/final value
  //
  //        == TLDR / IMPORTANT / TLDR / IMPORTANT ==
  // this is why sometimes a final clip can be longer or shorter!
  //        =========================================
  //
  // ------------------------------------------------------------
  int get originalClipNumberOfFrames => 
      originalClipFrameRate * originalClipDuration.inSeconds;

  Duration get originalClipPlaybackDuration => 
      originalClipDuration - transitionBufferDuration;

  // how long a clip should last during playback, in Duration
  // that can be different from its original speed
  // for instance if play back a 3 seconds video at 75% speed, we get:
  // 3 * (1 / 0.75) = 4
  Duration get actualClipDuration => Duration(
    // we use millis for greater precision
    // important: we internally use double for the calculation
    milliseconds: (originalClipDuration.inMilliseconds.toDouble() * 
        (1.0 / clipPlaybackSpeed)).round()
  );

  Duration get actualClipPlaybackDuration => 
      actualClipDuration - transitionBufferDuration;
}