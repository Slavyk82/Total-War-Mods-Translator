import '../../../models/common/service_exception.dart';

/// Base exception for concurrency service errors
class ConcurrencyException extends ServiceException {
  const ConcurrencyException(super.message, {super.code, super.details});
}

/// Transaction failed or rolled back
class TransactionException extends ConcurrencyException {
  TransactionException(
    super.message, {
    String? transactionId,
    Object? originalError,
  }) : super(
          code: 'TRANSACTION_ERROR',
          details: {
            'transaction_id': transactionId,
            'original_error': originalError?.toString(),
          },
        );
}

/// Maximum retry attempts exceeded
class MaxRetriesExceededException extends ConcurrencyException {
  MaxRetriesExceededException(
    super.message, {
    int? maxRetries,
    int? attemptsMade,
  }) : super(
          code: 'MAX_RETRIES_EXCEEDED',
          details: {
            'max_retries': maxRetries,
            'attempts_made': attemptsMade,
          },
        );
}
