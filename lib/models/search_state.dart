// lib/models/search_state.dart
class SearchState {
  final String query;
  final int resultCount;
  final DateTime startTime;

  SearchState({
    required this.query,
    this.resultCount = 0,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  SearchState copyWith({
    String? query,
    int? resultCount,
    DateTime? startTime,
  }) {
    return SearchState(
      query: query ?? this.query,
      resultCount: resultCount ?? this.resultCount,
      startTime: startTime ?? this.startTime,
    );
  }

  SearchState incrementCount() {
    return copyWith(resultCount: resultCount + 1);
  }
}