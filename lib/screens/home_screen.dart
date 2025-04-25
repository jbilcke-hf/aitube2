// lib/screens/home_screen.dart
import 'dart:async';
import 'package:aitube2/config/config.dart';
import 'package:aitube2/widgets/web_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:aitube2/screens/video_screen.dart';
import 'package:aitube2/screens/settings_screen.dart';
import 'package:aitube2/models/video_result.dart';
import 'package:aitube2/services/websocket_api_service.dart';
import 'package:aitube2/services/cache_service.dart';
import 'package:aitube2/widgets/video_card.dart';
import 'package:aitube2/widgets/search_box.dart';
import 'package:aitube2/theme/colors.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSearchQuery;
  
  const HomeScreen({
    super.key,
    this.initialSearchQuery,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _websocketService = WebSocketApiService();
  final _cacheService = CacheService();
  List<VideoResult> _results = [];
  bool _isSearching = false;
  String? _currentSearchQuery;
  StreamSubscription? _searchSubscription;
  static const int maxResults = 4;

  @override
  void initState() {
    super.initState();
    _initializeWebSocket();
    _setupSearchListener();
    
    // Check if we have an initial search query from URL parameters
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!;
      // Need to use Future.delayed to ensure WebSocket is initialized
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _search(widget.initialSearchQuery!);
        }
      });
    } else {
      _loadLastResults();
    }
  }

  Future<void> _loadLastResults() async {
    try {
      // Load most recent search results from cache
      final cachedResults = await _cacheService.getCachedSearchResults('');
      if (cachedResults.isNotEmpty && mounted) {
        setState(() {
          _results = cachedResults.take(maxResults).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading cached results: $e');
    }
  }

  void _setupSearchListener() {
    _searchSubscription = _websocketService.searchStream.listen((result) {
      if (mounted) {
        setState(() {
          if (_results.length < maxResults) {
            _results.add(result);
            // Cache each result as it comes in
            if (_currentSearchQuery != null) {
              _cacheService.cacheSearchResult(
                _currentSearchQuery!,
                result,
                _results.length,
              );
            }
            // Stop search if we've reached max results
            if (_results.length >= maxResults) {
              _stopSearch();
            }
          }
        });
      }
    });
  }

  void _stopSearch() {
    if (_currentSearchQuery != null) {
      _websocketService.stopContinuousSearch(_currentSearchQuery!);
      setState(() {
        _isSearching = false;
        _currentSearchQuery = null;
      });
    }
  }

  Future<void> _initializeWebSocket() async {
    try {
      await _websocketService.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to server: $e'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeWebSocket,
            ),
          ),
        );
      }
    }
  }

  Widget _buildConnectionStatus() {
    return StreamBuilder<ConnectionStatus>(
      stream: _websocketService.statusStream,
      builder: (context, connectionSnapshot) {
        return StreamBuilder<String>(
          stream: _websocketService.userRoleStream,
          builder: (context, roleSnapshot) {
            final status = connectionSnapshot.data ?? ConnectionStatus.disconnected;
            final userRole = roleSnapshot.data ?? 'anon';
            
            final backgroundColor = status == ConnectionStatus.connected
                ? Colors.green.withOpacity(0.1)
                : status == ConnectionStatus.error
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1);
            
            final textAndIconColor = status == ConnectionStatus.connected
                ? Colors.green
                : status == ConnectionStatus.error
                    ? Colors.red
                    : Colors.orange;

            final icon = status == ConnectionStatus.connected
                ? Icons.cloud_done
                : status == ConnectionStatus.error
                    ? Icons.cloud_off
                    : Icons.cloud_sync;

            // Modify the status message to include the user role
            String statusMessage;
            if (status == ConnectionStatus.connected) {
              statusMessage = userRole == 'anon' 
                  ? 'Connected as anon'
                  : 'Connected as $userRole';
            } else if (status == ConnectionStatus.error) {
              statusMessage = 'Disconnected';
            } else {
              statusMessage = _websocketService.statusMessage;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: textAndIconColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    statusMessage,
                    style: TextStyle(
                      color: textAndIconColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a search query')),
      );
      return;
    }

    // Clear previous results if query is different
    if (_currentSearchQuery != trimmedQuery) {
      setState(() {
        _results.clear();
        _isSearching = true;
      });
    }

    // Stop any existing search
    if (_currentSearchQuery != null) {
      _websocketService.stopContinuousSearch(_currentSearchQuery!);
    }

    // Update URL parameter for web builds
    if (kIsWeb) {
      updateUrlParameter('search', trimmedQuery);
    }

    try {
      // Check connection
      if (!_websocketService.isConnected) {
        await _websocketService.connect();
      }

      _currentSearchQuery = trimmedQuery;

      // Check cache first
      final cachedResults = await _cacheService.getCachedSearchResults(trimmedQuery);
      if (cachedResults.isNotEmpty) {
        if (mounted) {
          setState(() {
            _results = cachedResults.take(maxResults).toList();
          });
        }
        // If we have max results cached, stop searching
        if (cachedResults.length >= maxResults) {
          setState(() => _isSearching = false);
          return;
        }
      }

      // Start continuous search
      _websocketService.startContinuousSearch(trimmedQuery);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error performing search: $e')),
        );
        setState(() => _isSearching = false);
      }
    }
  }

  int _getColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1536) { // 2XL
      return 6;
    } else if (width >= 1280) { // XL
      return 5;
    } else if (width >= 1024) { // LG
      return 4;
    } else if (width >= 768) { // MD
      return 3;
    } else {
      return 2; // Default for small screens
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Configuration.instance.uiProductName),
        backgroundColor: AiTubeColors.background,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildConnectionStatus(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _stopSearch(); // Stop search but keep results
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBox(
              controller: _searchController,
              isSearching: _isSearching,
              enabled: _websocketService.isConnected,
              onSearch: _search,
              onCancel: _stopSearch,
            ),
          ),

          // Results Grid
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _isSearching
                          ? 'Generating videos...'
                          : 'Start by typing a description of the video you want to generate',
                      style: const TextStyle(color: AiTubeColors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  )
                  : MasonryGridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: _getColumnCount(context),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        _stopSearch(); // Stop search but keep results
                        
                        // Update URL parameter on web platform
                        if (kIsWeb) {
                          // Update view parameter and remove search parameter
                          updateUrlParameter('view', _results[index].title);
                          removeUrlParameter('search');
                        }
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoScreen(
                              video: _results[index],
                            ),
                          ),
                        );
                      },
                      child: VideoCard(video: _results[index]),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _searchController.dispose();
    _websocketService.dispose();
    super.dispose();
  }
}