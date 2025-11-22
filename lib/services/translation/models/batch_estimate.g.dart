// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_estimate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BatchEstimate _$BatchEstimateFromJson(Map<String, dynamic> json) =>
    BatchEstimate(
      batchId: json['batchId'] as String,
      totalUnits: (json['totalUnits'] as num).toInt(),
      estimatedInputTokens: (json['estimatedInputTokens'] as num).toInt(),
      estimatedOutputTokens: (json['estimatedOutputTokens'] as num).toInt(),
      totalEstimatedTokens: (json['totalEstimatedTokens'] as num).toInt(),
      providerCode: json['providerCode'] as String,
      modelName: json['modelName'] as String,
      unitsFromTm: (json['unitsFromTm'] as num).toInt(),
      unitsRequiringLlm: (json['unitsRequiringLlm'] as num).toInt(),
      tmReuseRate: (json['tmReuseRate'] as num).toDouble(),
      estimatedDurationSeconds: (json['estimatedDurationSeconds'] as num)
          .toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$BatchEstimateToJson(BatchEstimate instance) =>
    <String, dynamic>{
      'batchId': instance.batchId,
      'totalUnits': instance.totalUnits,
      'estimatedInputTokens': instance.estimatedInputTokens,
      'estimatedOutputTokens': instance.estimatedOutputTokens,
      'totalEstimatedTokens': instance.totalEstimatedTokens,
      'providerCode': instance.providerCode,
      'modelName': instance.modelName,
      'unitsFromTm': instance.unitsFromTm,
      'unitsRequiringLlm': instance.unitsRequiringLlm,
      'tmReuseRate': instance.tmReuseRate,
      'estimatedDurationSeconds': instance.estimatedDurationSeconds,
      'createdAt': instance.createdAt.toIso8601String(),
    };
