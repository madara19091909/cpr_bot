/// Cooperative cancellation for long-running jobs.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

class OperationCancelled implements Exception {
  const OperationCancelled();
  @override
  String toString() => 'OperationCancelled';
}
