import 'package:json_annotation/json_annotation.dart';
import 'language.dart' show BoolIntConverter;

part 'game_installation.g.dart';

/// Represents a detected Total War game installation on the user's system.
///
/// Game installations are auto-detected or manually configured by the user.
/// Each installation contains information about the game paths, Steam Workshop location,
/// and validation status.
@JsonSerializable()
class GameInstallation {
  /// Unique identifier (UUID)
  final String id;

  /// Game code identifier (e.g., 'wh3', 'troy', 'threekingdoms')
  @JsonKey(name: 'game_code')
  final String gameCode;

  /// Full game name (e.g., 'Total War: WARHAMMER III')
  @JsonKey(name: 'game_name')
  final String gameName;

  /// Path to game installation directory
  @JsonKey(name: 'installation_path')
  final String? installationPath;

  /// Path to Steam Workshop directory for this game
  @JsonKey(name: 'steam_workshop_path')
  final String? steamWorkshopPath;

  /// Steam App ID for this game
  @JsonKey(name: 'steam_app_id')
  final String? steamAppId;

  /// Whether this installation was automatically detected
  @JsonKey(name: 'is_auto_detected')
  @BoolIntConverter()
  final bool isAutoDetected;

  /// Whether the installation paths are currently valid
  @JsonKey(name: 'is_valid')
  @BoolIntConverter()
  final bool isValid;

  /// Unix timestamp when the installation was last validated
  @JsonKey(name: 'last_validated_at')
  final int? lastValidatedAt;

  /// Unix timestamp when the installation was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the installation was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const GameInstallation({
    required this.id,
    required this.gameCode,
    required this.gameName,
    this.installationPath,
    this.steamWorkshopPath,
    this.steamAppId,
    this.isAutoDetected = false,
    this.isValid = true,
    this.lastValidatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if the installation is currently valid
  bool get isValidInstallation => isValid;

  /// Returns true if paths are configured
  bool get hasValidPaths =>
      installationPath != null && installationPath!.isNotEmpty;

  /// Returns true if Steam Workshop path is configured
  bool get hasWorkshopPath =>
      steamWorkshopPath != null && steamWorkshopPath!.isNotEmpty;

  /// Returns true if this installation needs validation
  bool get needsValidation =>
      lastValidatedAt == null ||
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - lastValidatedAt! >
          86400; // 24 hours

  /// Returns a display name with game name and status
  String get displayName {
    final validStatus = isValid ? '' : ' (Invalid)';
    return '$gameName$validStatus';
  }

  GameInstallation copyWith({
    String? id,
    String? gameCode,
    String? gameName,
    String? installationPath,
    String? steamWorkshopPath,
    String? steamAppId,
    bool? isAutoDetected,
    bool? isValid,
    int? lastValidatedAt,
    int? createdAt,
    int? updatedAt,
  }) {
    return GameInstallation(
      id: id ?? this.id,
      gameCode: gameCode ?? this.gameCode,
      gameName: gameName ?? this.gameName,
      installationPath: installationPath ?? this.installationPath,
      steamWorkshopPath: steamWorkshopPath ?? this.steamWorkshopPath,
      steamAppId: steamAppId ?? this.steamAppId,
      isAutoDetected: isAutoDetected ?? this.isAutoDetected,
      isValid: isValid ?? this.isValid,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory GameInstallation.fromJson(Map<String, dynamic> json) =>
      _$GameInstallationFromJson(json);

  Map<String, dynamic> toJson() => _$GameInstallationToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameInstallation &&
        other.id == id &&
        other.gameCode == gameCode &&
        other.gameName == gameName &&
        other.installationPath == installationPath &&
        other.steamWorkshopPath == steamWorkshopPath &&
        other.steamAppId == steamAppId &&
        other.isAutoDetected == isAutoDetected &&
        other.isValid == isValid &&
        other.lastValidatedAt == lastValidatedAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      gameCode.hashCode ^
      gameName.hashCode ^
      installationPath.hashCode ^
      steamWorkshopPath.hashCode ^
      steamAppId.hashCode ^
      isAutoDetected.hashCode ^
      isValid.hashCode ^
      lastValidatedAt.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() => 'GameInstallation(id: $id, gameCode: $gameCode, gameName: $gameName, isValid: $isValid)';
}
