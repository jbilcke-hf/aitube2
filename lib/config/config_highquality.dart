class ConfigurationHighQuality {

    // how many clips should be stored in advance
  static const int renderQueueBufferSize = 5;

  static const int minimumBufferPercentToStartPlayback = 30;

  static const int renderQueueMaxConcurrentGenerations = 3;
  static const int originalClipWidth = 736;
  static const int originalClipHeight = 448;

  // to do more with less, we slow down the videos (a 3s video will become a 4s video)
  // but if you are GPU rich feel feel to play them back at 100% of their speed!
  static const double clipPlaybackSpeed = 1.0;
}