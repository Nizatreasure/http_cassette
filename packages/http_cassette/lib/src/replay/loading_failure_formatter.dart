import '../cassette/decoder.dart';
import 'diagnostic_formatting.dart';
import 'loading_failure.dart';

/// Deterministically formats safe replay cassette loading failures.
final class ReplayCassetteLoadFailureFormatter {
  /// Creates the default replay-loading formatter.
  const ReplayCassetteLoadFailureFormatter();

  /// Formats [failure] without logging or inspecting cassette bytes.
  String format(ReplayCassetteLoadFailure failure) => <String>[
        'HTTP Cassette failure: ${failure.envelope.summary}',
        'Category: ${failure.envelope.category.name}',
        'Cassette: ${formatReplayDiagnosticCassetteName(failure.cassetteName.value)}',
        ...switch (failure) {
          ReplayCassetteStoreReadFailure() => _formatStoreRead(failure),
          ReplayCassetteDecodeFailure() => _formatDecode(failure),
        },
        'Network access: disabled; no real request was made',
      ].join('\n');

  List<String> _formatStoreRead(ReplayCassetteStoreReadFailure failure) =>
      <String>[
        'Loading source: store read',
        'Store failure: ${failure.diagnostic.storeFailureKind.name}',
      ];

  List<String> _formatDecode(ReplayCassetteDecodeFailure failure) {
    final diagnostic = failure.diagnostic;
    final observedSchemaVersion =
        diagnostic.observedSchemaVersion ?? '<not safely representable>';
    final schemaVersionLine = 'Schema version: '
        'observed=$observedSchemaVersion; '
        'supported=${diagnostic.supportedSchemaVersion}';
    return <String>[
      'Loading source: cassette decoder',
      'Decode failure: ${diagnostic.failureKind.name}',
      'Location: ${diagnostic.location.isEmpty ? '<root>' : diagnostic.location}',
      if (diagnostic.line != null)
        'Source position: line=${diagnostic.line}; column=${diagnostic.column}',
      if (_isVersionFailure(diagnostic.failureKind)) schemaVersionLine,
      if (diagnostic.maximumBytes != null)
        'Cassette limit: ${diagnostic.maximumBytes} bytes',
    ];
  }
}

/// Human-readable formatting for replay cassette loading failures.
extension ReplayCassetteLoadFailureFormatting on ReplayCassetteLoadFailure {
  /// Formats this failure with [formatter].
  String format([
    ReplayCassetteLoadFailureFormatter formatter =
        const ReplayCassetteLoadFailureFormatter(),
  ]) =>
      formatter.format(this);
}

bool _isVersionFailure(CassetteDecodeFailureKind kind) =>
    kind == CassetteDecodeFailureKind.unsupportedOlderVersion ||
    kind == CassetteDecodeFailureKind.unsupportedNewerVersion;
