// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation_issue.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ValidationIssue _$ValidationIssueFromJson(Map<String, dynamic> json) =>
    ValidationIssue(
      type: $enumDecode(_$ValidationIssueTypeEnumMap, json['type']),
      severity: $enumDecode(_$ValidationSeverityEnumMap, json['severity']),
      description: json['description'] as String,
      suggestion: json['suggestion'] as String?,
      autoFixable: json['autoFixable'] as bool? ?? false,
      autoFixValue: json['autoFixValue'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$ValidationIssueToJson(ValidationIssue instance) =>
    <String, dynamic>{
      'type': _$ValidationIssueTypeEnumMap[instance.type]!,
      'severity': _$ValidationSeverityEnumMap[instance.severity]!,
      'description': instance.description,
      'suggestion': instance.suggestion,
      'autoFixable': instance.autoFixable,
      'autoFixValue': instance.autoFixValue,
      'metadata': instance.metadata,
    };

const _$ValidationIssueTypeEnumMap = {
  ValidationIssueType.emptyTranslation: 'emptyTranslation',
  ValidationIssueType.lengthDifference: 'lengthDifference',
  ValidationIssueType.missingVariables: 'missingVariables',
  ValidationIssueType.whitespaceIssue: 'whitespaceIssue',
  ValidationIssueType.punctuationMismatch: 'punctuationMismatch',
  ValidationIssueType.caseMismatch: 'caseMismatch',
  ValidationIssueType.missingNumbers: 'missingNumbers',
  ValidationIssueType.modifiedNumbers: 'modifiedNumbers',
};

const _$ValidationSeverityEnumMap = {
  ValidationSeverity.error: 'error',
  ValidationSeverity.warning: 'warning',
  ValidationSeverity.info: 'info',
};
