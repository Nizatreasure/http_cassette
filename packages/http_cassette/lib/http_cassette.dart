/// Transport-neutral foundations for HTTP recording and replay.
///
/// Recording and replay are not implemented yet. The current API provides the
/// structured diagnostic foundations used by later behaviour.
library;

export 'src/cassette/name.dart';
export 'src/configuration/body_limits.dart';
export 'src/configuration/matching_configuration.dart';
export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/exception.dart';
export 'src/diagnostics/formatter.dart';
export 'src/model/headers.dart';
export 'src/model/http_message.dart';
export 'src/model/outcome.dart';
