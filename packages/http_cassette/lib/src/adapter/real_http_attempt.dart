import '../model/outcome.dart';

/// Performs the adapter's one prepared real HTTP transport attempt.
///
/// The callback is argument-free because the adapter retains ownership of its
/// transport request and any replacement streams. It must return either a
/// canonical response outcome or a canonical transport failure.
typedef RealHttpAttempt = Future<CassetteOutcome> Function();
