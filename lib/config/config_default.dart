
abstract class DefaultConfiguration {

  // how many clips should be stored in advance
  static const int renderQueueBufferSize = 4;

  // how many requests for clips can be run in parallel
  static const int renderQueueMaxConcurrentGenerations = 2;

  // start playback as soon as we have 1 video over 4
  static const int minimumBufferPercentToStartPlayback = 25;

  // transition time between each clip
  // the exit (older) clip will see its playback time reduced by this amount
  static const transitionBufferDuration = Duration(milliseconds: 300);

  // how long a generated clip should be, in Duration
  static const originalClipDuration = Duration(seconds: 4);


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
  static const int numInferenceSteps = 30;

  // original frame-rate of each clip (before we slow them down)
  // in frames per second (so an integer)
  static const int originalClipFrameRate = 25;

  static const int originalClipWidth = 544; // 512
  static const int originalClipHeight = 320; // 320

  // to do more with less, we slow down the videos (a 3s video will become a 4s video)
  // but if you are GPU rich feel feel to play them back at 100% of their speed!
  static const double clipPlaybackSpeed = 0.7;
}