// lib/widgets/search_box.dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/cache_service.dart';

class SearchBox extends StatefulWidget {
  final TextEditingController controller;
  final bool isSearching;
  final bool enabled;
  final Function(String) onSearch;
  final VoidCallback onCancel;

  const SearchBox({
    super.key,
    required this.controller,
    required this.isSearching,
    required this.enabled,
    required this.onSearch,
    required this.onCancel,
  });

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _focusNode = FocusNode();
  final _cacheService = CacheService();
  bool _showSuggestions = false;
  List<String> _suggestions = [];
  OverlayEntry? _overlayEntry;
  final _layerLink = LayerLink();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onSearchTextChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _showSuggestions = true;
      _updateSuggestions();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hideSuggestions();
      });
    }
  }

  void _onSearchTextChanged() {
    if (_focusNode.hasFocus && !_isComposing) {
      _updateSuggestions();
    }
  }

  Future<void> _updateSuggestions() async {
    if (!mounted) return;

    final query = widget.controller.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _hideOverlay();
      });
      return;
    }

    try {
      final results = await _cacheService.getCachedSearchResults('');
      if (!mounted) return;

      setState(() {
        _suggestions = results
            .map((result) => result.title)
            .where((title) => title.toLowerCase().contains(query))
            .take(8)
            .toList();

        if (_suggestions.isNotEmpty && _focusNode.hasFocus) {
          _showOverlay();
        } else {
          _hideOverlay();
        }
      });
    } catch (e) {
      debugPrint('Error updating suggestions: $e');
    }
  }

  void _showOverlay() {
    _hideOverlay();

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 5.0,
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 5.0),
          child: Material(
            elevation: 4.0,
            color: AiTubeColors.surface,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions.map((suggestion) {
                return ListTile(
                  title: Text(
                    suggestion,
                    style: const TextStyle(color: AiTubeColors.onSurface),
                  ),
                  onTap: () {
                    widget.controller.text = suggestion;
                    _hideSuggestions();
                    _handleSubmitted(suggestion);
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _hideSuggestions() {
    setState(() {
      _showSuggestions = false;
      _hideOverlay();
    });
  }

  void _handleSubmitted(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isNotEmpty) {
      _hideSuggestions();
      FocusScope.of(context).unfocus();
      widget.onSearch(trimmedValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          style: const TextStyle(color: AiTubeColors.onBackground),
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: _handleSubmitted,
          onTapOutside: (_) {
            FocusScope.of(context).unfocus();
          },
          decoration: InputDecoration(
            hintText: 'Describe a video you want to generate...',
            hintStyle: const TextStyle(color: AiTubeColors.onSurfaceVariant),
            filled: true,
            fillColor: AiTubeColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            suffixIcon: widget.isSearching
                ? IconButton(
                    icon: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    onPressed: widget.onCancel,
                  )
                : IconButton(
                    icon: const Icon(
                      Icons.search,
                      color: AiTubeColors.onSurfaceVariant,
                    ),
                    onPressed: () => _handleSubmitted(widget.controller.text),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    widget.controller.removeListener(_onSearchTextChanged);
    super.dispose();
  }
}