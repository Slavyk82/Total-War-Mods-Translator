// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workshop_mod_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkshopModInfo _$WorkshopModInfoFromJson(Map<String, dynamic> json) =>
    WorkshopModInfo(
      workshopId: json['workshopId'] as String,
      title: json['title'] as String,
      workshopUrl: json['workshopUrl'] as String,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      timeUpdated: (json['timeUpdated'] as num?)?.toInt(),
      timeCreated: (json['timeCreated'] as num?)?.toInt(),
      subscriptions: (json['subscriptions'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      appId: (json['appId'] as num).toInt(),
    );

Map<String, dynamic> _$WorkshopModInfoToJson(WorkshopModInfo instance) =>
    <String, dynamic>{
      'workshopId': instance.workshopId,
      'title': instance.title,
      'workshopUrl': instance.workshopUrl,
      'fileSize': instance.fileSize,
      'timeUpdated': instance.timeUpdated,
      'timeCreated': instance.timeCreated,
      'subscriptions': instance.subscriptions,
      'tags': instance.tags,
      'appId': instance.appId,
    };
