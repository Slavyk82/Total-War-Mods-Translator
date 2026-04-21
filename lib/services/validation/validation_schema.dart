/// The schema version written on rows that have been (re)validated with
/// the current validation logic. Rows with `validation_schema_version`
/// less than this constant are considered legacy and get rescanned on
/// next boot via [ValidationRescanService].
///
/// Bump this whenever the validation logic changes in a way that
/// invalidates previously persisted `validation_issues`:
/// - v1: initial structured-JSON format.
/// - v2: numbers rule removed (too noisy — flagged matching numbers
///   because of Dart's identity-based list equality and otherwise
///   produced low-signal warnings); v1 rows may carry stale
///   "Numbers don't match source" warnings and need to be rescanned.
/// - v3: markup rule no longer flags "Source text has unbalanced markup
///   tags" when the translation preserves the exact same tag sequence
///   (e.g. Creative Assembly's `[PH]` placeholder convention); v2 rows
///   may carry stale warnings on those preserved-orphan cases.
const int kCurrentValidationSchemaVersion = 3;
