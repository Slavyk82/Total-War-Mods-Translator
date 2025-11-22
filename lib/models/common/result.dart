/// Result type for operation success or failure.
///
/// This is a sealed class that represents either a successful result [Ok]
/// or a failed result [Err]. It follows functional programming patterns
/// for error handling without using exceptions.
///
/// Example:
/// ```dart
/// Result<User, String> fetchUser(String id) {
///   try {
///     final user = database.getUser(id);
///     return Ok(user);
///   } catch (e) {
///     return Err('Failed to fetch user: $e');
///   }
/// }
///
/// final result = fetchUser('123');
/// result.when(
///   ok: (user) => print('Got user: ${user.name}'),
///   err: (error) => print('Error: $error'),
/// );
/// ```
sealed class Result<T, E> {
  const Result();

  /// Execute different code paths based on result type
  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) {
    return switch (this) {
      Ok(value: final value) => ok(value),
      Err(error: final error) => err(error),
    };
  }

  /// Map the success value to a new type
  Result<R, E> map<R>(R Function(T value) transform) {
    return when(
      ok: (value) => Ok(transform(value)),
      err: (error) => Err(error),
    );
  }

  /// Map the error value to a new type
  Result<T, R> mapError<R>(R Function(E error) transform) {
    return when(
      ok: (value) => Ok(value),
      err: (error) => Err(transform(error)),
    );
  }

  /// Check if this is a success result
  bool get isOk => this is Ok<T, E>;

  /// Check if this is an error result
  bool get isErr => this is Err<T, E>;

  /// Get the success value or throw if error
  T get value => when(
        ok: (value) => value,
        err: (error) => throw StateError('Called value on Err: $error'),
      );

  /// Get the error value or throw if success
  E get error => when(
        ok: (value) => throw StateError('Called error on Ok'),
        err: (error) => error,
      );

  /// Get the success value or return a default
  T getOrElse(T defaultValue) => when(
        ok: (value) => value,
        err: (_) => defaultValue,
      );

  /// Get the success value or compute from error
  T getOrElseCompute(T Function(E error) compute) => when(
        ok: (value) => value,
        err: (error) => compute(error),
      );

  /// Get the success value or throw if error (alias for value getter)
  T unwrap() => value;

  /// Get the error value or throw if success (alias for error getter)
  E unwrapErr() => error;
}

/// Successful result containing a value
final class Ok<T, E> extends Result<T, E> {
  @override
  final T value;

  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ok<T, E> && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Failed result containing an error
final class Err<T, E> extends Result<T, E> {
  @override
  final E error;

  const Err(this.error);

  @override
  String toString() => 'Err($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Err<T, E> && error == other.error;

  @override
  int get hashCode => error.hashCode;
}
