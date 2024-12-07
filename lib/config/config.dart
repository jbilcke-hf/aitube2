
import 'package:aitube2/config/config_default.dart';
import 'package:aitube2/config/config_highquality.dart';

class Configuration {

  // how many clips should be stored in advance
  static const int renderQueueBufferSize = ConfigurationHighQuality.renderQueueBufferSize;

  // how many requests for clips can be run in parallel
  static const int renderQueueMaxConcurrentGenerations = ConfigurationHighQuality.renderQueueMaxConcurrentGenerations;

  // start playback as soon as we have 1 video over 4
  static const int minimumBufferPercentToStartPlayback = DefaultConfiguration.minimumBufferPercentToStartPlayback;

  // transition time between each clip
  // the exit (older) clip will see its playback time reduced by this amount
  static const transitionBufferDuration = DefaultConfiguration.transitionBufferDuration;

  // how long a generated clip should be, in Duration
  static const originalClipDuration = DefaultConfiguration.originalClipDuration;


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
  static const int numInferenceSteps = DefaultConfiguration.numInferenceSteps;

  // original frame-rate of each clip (before we slow them down)
  // in frames per second (so an integer)
  static const int originalClipFrameRate = DefaultConfiguration.originalClipFrameRate;

  static const int originalClipWidth = ConfigurationHighQuality.originalClipWidth;
  static const int originalClipHeight = ConfigurationHighQuality.originalClipHeight;

  // to do more with less, we slow down the videos (a 3s video will become a 4s video)
  // but if you are GPU rich feel feel to play them back at 100% of their speed!
  static const double clipPlaybackSpeed = ConfigurationHighQuality.clipPlaybackSpeed;

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
  static final originalClipNumberOfFrames = DefaultConfiguration.originalClipFrameRate * DefaultConfiguration.originalClipDuration.inSeconds;

  static final originalClipPlaybackDuration = DefaultConfiguration.originalClipDuration - DefaultConfiguration.transitionBufferDuration;

  // how long a clip should last during playback, in Duration
  // that can be different from its original speed
  // for instance if play back a 3 seconds video at 75% speed, we get:
  // 3 * (1 / 0.75) = 4
  static final actualClipDuration = Duration(
    // we use millis for greater precision
    milliseconds: (
      // important: we internally use double for the calculation
      DefaultConfiguration.originalClipDuration.inMilliseconds.toDouble() * (1.0 / ConfigurationHighQuality.clipPlaybackSpeed)
    ).round()
  );

  static final actualClipPlaybackDuration = actualClipDuration - DefaultConfiguration.transitionBufferDuration;

}