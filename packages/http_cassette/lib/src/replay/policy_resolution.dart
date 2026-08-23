import 'configuration.dart';

/// Resolves a session override against its engine-level [defaultPolicy].
ReplayPolicy resolveReplayPolicy({
  required ReplayPolicy defaultPolicy,
  required ReplayOptions options,
}) =>
    options.policy ?? defaultPolicy;
