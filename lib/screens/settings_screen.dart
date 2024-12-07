import 'package:flutter/material.dart';
import '../services/cache_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _promptController = TextEditingController();
  final _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _promptController.text = _settingsService.videoPromptPrefix;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: StreamBuilder<CacheStats>(
        stream: CacheService().statsStream,
        builder: (context, snapshot) {
          final stats = snapshot.data;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Video Prompt Prefix Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Video Generation',
                        style: TextStyle(
                          color: AiTubeColors.onBackground,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _promptController,
                        decoration: const InputDecoration(
                          labelText: 'Video Prompt Prefix',
                          helperText: 'Text to prepend to all video generation prompts',
                          helperMaxLines: 2,
                        ),
                        onChanged: (value) {
                          _settingsService.setVideoPromptPrefix(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Cache Card (existing code)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cache',
                        style: TextStyle(
                          color: AiTubeColors.onBackground,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStatRow(
                        'Items in cache',
                        '${stats?.totalItems ?? 0}',
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        'Total size',
                        '${(stats?.totalSizeMB ?? 0).toStringAsFixed(2)} MB',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear Cache'),
                              content: const Text(
                                'Are you sure you want to clear all cached data? '
                                'This will remove all saved search results and videos.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await CacheService().clearCache();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cache cleared'),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Cache'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AiTubeColors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AiTubeColors.onBackground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
