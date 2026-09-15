/// Controls how long cassette-store operations may remain pending.
final class StoreOperationConfiguration {
  /// Creates store-operation configuration.
  factory StoreOperationConfiguration({
    Duration timeout = defaultTimeout,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'The store operation timeout must be positive.',
      );
    }
    return StoreOperationConfiguration._(timeout);
  }

  const StoreOperationConfiguration._(this.timeout);

  /// The default maximum wait for one store operation.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// The maximum time allowed for one store operation.
  final Duration timeout;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreOperationConfiguration && timeout == other.timeout;

  @override
  int get hashCode => timeout.hashCode;
}
