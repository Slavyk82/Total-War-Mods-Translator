/// Validation utilities for common input validation patterns.
///
/// Provides static methods for validating common types of input data
/// used throughout the TWMT application.
class Validators {
  // Private constructor to prevent instantiation
  Validators._();

  /// Email validation regex pattern
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// UUID v4 validation regex pattern
  static final _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Language code validation (ISO 639-1)
  static final _languageCodeRegex = RegExp(r'^[a-z]{2}$');

  /// Language code with region (ISO 639-1 + ISO 3166-1)
  static final _languageCodeWithRegionRegex = RegExp(r'^[a-z]{2}[-_][A-Z]{2}$');

  /// Validates an email address.
  ///
  /// Returns null if valid, error message if invalid.
  ///
  /// Example:
  /// ```dart
  /// final error = Validators.validateEmail('user@example.com');
  /// if (error != null) {
  ///   // Handle error
  /// }
  /// ```
  static String? validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      return 'Email is required';
    }

    if (!_emailRegex.hasMatch(email)) {
      return 'Invalid email format';
    }

    return null;
  }

  /// Validates a UUID (v4).
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) {
      return 'UUID is required';
    }

    if (!_uuidRegex.hasMatch(uuid)) {
      return 'Invalid UUID format';
    }

    return null;
  }

  /// Validates a string length.
  ///
  /// [value] - String to validate
  /// [minLength] - Minimum length (inclusive), null for no minimum
  /// [maxLength] - Maximum length (inclusive), null for no maximum
  /// [fieldName] - Name of the field for error messages
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateLength(
    String? value, {
    int? minLength,
    int? maxLength,
    String fieldName = 'Field',
  }) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }

    if (minLength != null && value.length < minLength) {
      return '$fieldName must be at least $minLength characters';
    }

    if (maxLength != null && value.length > maxLength) {
      return '$fieldName must not exceed $maxLength characters';
    }

    return null;
  }

  /// Validates a required string field.
  ///
  /// Returns null if valid (non-null and non-empty), error message if invalid.
  static String? validateRequired(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    return null;
  }

  /// Validates a numeric value is within a range.
  ///
  /// [value] - Number to validate
  /// [min] - Minimum value (inclusive), null for no minimum
  /// [max] - Maximum value (inclusive), null for no maximum
  /// [fieldName] - Name of the field for error messages
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateRange(
    num? value, {
    num? min,
    num? max,
    String fieldName = 'Value',
  }) {
    if (value == null) {
      return '$fieldName is required';
    }

    if (min != null && value < min) {
      return '$fieldName must be at least $min';
    }

    if (max != null && value > max) {
      return '$fieldName must not exceed $max';
    }

    return null;
  }

  /// Validates a date is within a range.
  ///
  /// [date] - Date to validate
  /// [minDate] - Minimum date (inclusive), null for no minimum
  /// [maxDate] - Maximum date (inclusive), null for no maximum
  /// [fieldName] - Name of the field for error messages
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateDateRange(
    DateTime? date, {
    DateTime? minDate,
    DateTime? maxDate,
    String fieldName = 'Date',
  }) {
    if (date == null) {
      return '$fieldName is required';
    }

    if (minDate != null && date.isBefore(minDate)) {
      return '$fieldName must be after ${minDate.toLocal()}';
    }

    if (maxDate != null && date.isAfter(maxDate)) {
      return '$fieldName must be before ${maxDate.toLocal()}';
    }

    return null;
  }

  /// Validates a file path.
  ///
  /// Checks for:
  /// - Non-empty path
  /// - Valid path characters (platform-specific)
  /// - Optional extension validation
  ///
  /// [path] - File path to validate
  /// [allowedExtensions] - Optional list of allowed extensions (e.g., ['.txt', '.csv'])
  /// [baseDirectory] - Optional base directory to restrict paths within
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateFilePath(
    String? path, {
    List<String>? allowedExtensions,
    String? baseDirectory,
  }) {
    if (path == null || path.trim().isEmpty) {
      return 'File path is required';
    }

    // 1. Check for path traversal sequences
    if (path.contains('..') || path.contains('..\\') || path.contains('../')) {
      return 'Path traversal not allowed';
    }

    // 2. Prevent absolute paths (Windows-specific)
    if (path.contains(':') || path.startsWith('\\\\')) {
      return 'Absolute paths not allowed';
    }

    // 3. Check for invalid characters (common across platforms)
    final invalidChars = ['<', '>', '|', '\x00', '*', '?'];
    for (final char in invalidChars) {
      if (path.contains(char)) {
        return 'File path contains invalid character: $char';
      }
    }

    // 4. Check extension if specified
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      final hasValidExtension = allowedExtensions.any((ext) {
        return path.toLowerCase().endsWith(ext.toLowerCase());
      });

      if (!hasValidExtension) {
        return 'File must have one of these extensions: ${allowedExtensions.join(", ")}';
      }
    }

    return null;
  }

  /// Validates a language code (ISO 639-1).
  ///
  /// Accepts codes like "en", "fr", "de", etc.
  /// Optionally accepts codes with region like "en-US", "fr-FR".
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateLanguageCode(
    String? code, {
    bool allowRegion = false,
  }) {
    if (code == null || code.isEmpty) {
      return 'Language code is required';
    }

    if (allowRegion) {
      if (!_languageCodeRegex.hasMatch(code) &&
          !_languageCodeWithRegionRegex.hasMatch(code)) {
        return 'Invalid language code format (expected: "en" or "en-US")';
      }
    } else {
      if (!_languageCodeRegex.hasMatch(code)) {
        return 'Invalid language code format (expected: two lowercase letters)';
      }
    }

    return null;
  }

  /// Validates a quality score.
  ///
  /// Quality scores must be between 0.0 and 1.0 (inclusive).
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateQualityScore(double? score) {
    if (score == null) {
      return 'Quality score is required';
    }

    if (score < 0.0 || score > 1.0) {
      return 'Quality score must be between 0.0 and 1.0';
    }

    return null;
  }

  /// Validates a URL.
  ///
  /// Checks for valid HTTP/HTTPS URLs.
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'URL is required';
    }

    try {
      final uri = Uri.parse(url);

      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return 'URL must start with http:// or https://';
      }

      if (!uri.hasAuthority) {
        return 'Invalid URL format';
      }

      return null;
    } catch (e) {
      return 'Invalid URL format: $e';
    }
  }

  /// Validates a Workshop ID (Steam Workshop).
  ///
  /// Workshop IDs are numeric strings.
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateWorkshopId(String? workshopId) {
    if (workshopId == null || workshopId.isEmpty) {
      return 'Workshop ID is required';
    }

    if (!RegExp(r'^\d+$').hasMatch(workshopId)) {
      return 'Workshop ID must be numeric';
    }

    return null;
  }

  /// Validates a password meets minimum security requirements.
  ///
  /// Requirements:
  /// - At least [minLength] characters (default: 8)
  /// - At least one uppercase letter (if [requireUppercase] is true)
  /// - At least one lowercase letter (if [requireLowercase] is true)
  /// - At least one digit (if [requireDigit] is true)
  /// - At least one special character (if [requireSpecial] is true)
  ///
  /// Returns null if valid, error message if invalid.
  static String? validatePassword(
    String? password, {
    int minLength = 8,
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireDigit = true,
    bool requireSpecial = false,
  }) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < minLength) {
      return 'Password must be at least $minLength characters';
    }

    if (requireUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (requireLowercase && !password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (requireDigit && !password.contains(RegExp(r'\d'))) {
      return 'Password must contain at least one digit';
    }

    if (requireSpecial &&
        !password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }

    return null;
  }

  /// Validates that two values match (e.g., password confirmation).
  ///
  /// Returns null if values match, error message if they don't.
  static String? validateMatch(
    String? value1,
    String? value2, {
    String fieldName = 'Values',
  }) {
    if (value1 != value2) {
      return '$fieldName do not match';
    }

    return null;
  }

  /// Validates multiple validators and returns the first error found.
  ///
  /// Example:
  /// ```dart
  /// final error = Validators.validateAll([
  ///   () => Validators.validateRequired(name),
  ///   () => Validators.validateLength(name, minLength: 3),
  ///   () => Validators.validateEmail(email),
  /// ]);
  /// ```
  ///
  /// Returns null if all validators pass, first error message otherwise.
  static String? validateAll(List<String? Function()> validators) {
    for (final validator in validators) {
      final error = validator();
      if (error != null) {
        return error;
      }
    }

    return null;
  }
}
