import '../model/outcome.dart';

/// Performs the adapter's one prepared real HTTP transport attempt.
///
/// The adapter retains the transport request and any replacement streams, so
/// the callback needs no arguments. It completes with either a canonical
/// response or a portable transport failure. It must not be invoked more than
/// once for one interception and is never invoked during replay.
typedef RealHttpAttempt = Future<CassetteOutcome> Function();
