import 'dart:async';

class TransactionLedgerRefreshSignal {
  TransactionLedgerRefreshSignal._();

  static final TransactionLedgerRefreshSignal instance =
      TransactionLedgerRefreshSignal._();

  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get stream => _controller.stream;

  void emit() => _controller.add(null);
}
