/// Formats a validated logical cassette [name] within the diagnostic bound.
String formatReplayDiagnosticCassetteName(String name) {
  if (name.length <= maximumReplayDiagnosticCassetteNameLength) {
    return name;
  }
  return '${name.substring(0, maximumReplayDiagnosticCassetteNameLength)}... '
      '(${name.length} characters)';
}

/// Formats at most the first 16 recorded [indices] with an omitted count.
String formatReplayDiagnosticIndices(List<int> indices) {
  final displayedCount = indices.length < maximumReplayDiagnosticIndices
      ? indices.length
      : maximumReplayDiagnosticIndices;
  final output = indices.take(displayedCount).join(', ');
  final omittedCount = indices.length - displayedCount;
  if (omittedCount == 0) {
    return output;
  }
  return '$output ... ($omittedCount omitted)';
}

/// Maximum logical cassette-name characters displayed in a replay diagnostic.
const maximumReplayDiagnosticCassetteNameLength = 128;

/// Maximum recorded interaction indices displayed in a replay diagnostic.
const maximumReplayDiagnosticIndices = 16;
