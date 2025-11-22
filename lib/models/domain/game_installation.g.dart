// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_installation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GameInstallation _$GameInstallationFromJson(Map<String, dynamic> json) =>
    GameInstallation(
      id: json['id'] as String,
      gameCode: json['game_code'] as String,
      gameName: json['game_name'] as String,
      installationPath: json['installation_path'] as String?,
      steamWorkshopPath: json['steam_workshop_path'] as String?,
      steamAppId: json['steam_app_id'] as String?,
      isAutoDetected: json['is_auto_detected'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_auto_detected']),
      isValid: json['is_valid'] == null
          ? true
          : const BoolIntConverter().fromJson(json['is_valid']),
      lastValidatedAt: (json['last_validated_at'] as num?)?.toInt(),
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );

Map<String, dynamic> _$GameInstallationToJson(
  GameInstallation instance,
) => <String, dynamic>{
  'id': instance.id,
  'game_code': instance.gameCode,
  'game_name': instance.gameName,
  'installation_path': instance.installationPath,
  'steam_workshop_path': instance.steamWorkshopPath,
  'steam_app_id': instance.steamAppId,
  'is_auto_detected': const BoolIntConverter().toJson(instance.isAutoDetected),
  'is_valid': const BoolIntConverter().toJson(instance.isValid),
  'last_validated_at': instance.lastValidatedAt,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
};
