import 'package:json_annotation/json_annotation.dart';

part 'pagination.g.dart';

/// Paginated result for list operations.
///
/// Contains a list of items along with pagination metadata.
///
/// Example:
/// ```dart
/// final result = PaginatedResult<User>(
///   items: users,
///   totalCount: 150,
///   page: 1,
///   pageSize: 20,
/// );
///
/// print('Showing ${result.items.length} of ${result.totalCount}');
/// print('Total pages: ${result.totalPages}');
/// print('Has more: ${result.hasNextPage}');
/// ```
@JsonSerializable(genericArgumentFactories: true)
class PaginatedResult<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  /// Total number of pages
  int get totalPages => (totalCount / pageSize).ceil();

  /// Check if there are more pages
  bool get hasNextPage => page < totalPages;

  /// Check if there is a previous page
  bool get hasPreviousPage => page > 1;

  /// Get the starting item index (1-based)
  int get startIndex => (page - 1) * pageSize + 1;

  /// Get the ending item index (1-based)
  int get endIndex {
    final end = page * pageSize;
    return end > totalCount ? totalCount : end;
  }

  /// Check if this is the first page
  bool get isFirstPage => page == 1;

  /// Check if this is the last page
  bool get isLastPage => page >= totalPages;

  /// Check if the result is empty
  bool get isEmpty => items.isEmpty;

  /// Check if the result is not empty
  bool get isNotEmpty => items.isNotEmpty;

  /// Creates a copy with optional new values
  PaginatedResult<T> copyWith({
    List<T>? items,
    int? totalCount,
    int? page,
    int? pageSize,
  }) {
    return PaginatedResult<T>(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  factory PaginatedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) =>
      _$PaginatedResultFromJson(json, fromJsonT);

  Map<String, dynamic> toJson(Object? Function(T) toJsonT) =>
      _$PaginatedResultToJson(this, toJsonT);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PaginatedResult<T>) return false;
    if (items.length != other.items.length) return false;
    for (int i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return totalCount == other.totalCount &&
        page == other.page &&
        pageSize == other.pageSize;
  }

  @override
  int get hashCode =>
      Object.hash(items.length, totalCount, page, pageSize);

  @override
  String toString() =>
      'PaginatedResult<$T>(items: ${items.length}, totalCount: $totalCount, page: $page, pageSize: $pageSize)';
}

/// Pagination parameters for queries.
///
/// Example:
/// ```dart
/// final params = PaginationParams(page: 2, pageSize: 50);
/// final users = await userRepository.getUsers(params);
/// ```
@JsonSerializable()
class PaginationParams {
  final int page;
  final int pageSize;

  const PaginationParams({
    this.page = 1,
    this.pageSize = 20,
  });

  /// Calculate offset for SQL queries
  int get offset => (page - 1) * pageSize;

  /// Get limit for SQL queries
  int get limit => pageSize;

  /// Create params for the next page
  PaginationParams nextPage() => PaginationParams(
        page: page + 1,
        pageSize: pageSize,
      );

  /// Create params for the previous page
  PaginationParams previousPage() => PaginationParams(
        page: page > 1 ? page - 1 : 1,
        pageSize: pageSize,
      );

  /// Create params for the first page
  PaginationParams firstPage() => PaginationParams(
        page: 1,
        pageSize: pageSize,
      );

  /// Creates a copy with optional new values
  PaginationParams copyWith({
    int? page,
    int? pageSize,
  }) {
    return PaginationParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  factory PaginationParams.fromJson(Map<String, dynamic> json) =>
      _$PaginationParamsFromJson(json);

  Map<String, dynamic> toJson() => _$PaginationParamsToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaginationParams &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(page, pageSize);

  @override
  String toString() =>
      'PaginationParams(page: $page, pageSize: $pageSize)';
}
