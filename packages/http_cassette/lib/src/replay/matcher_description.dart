import '../configuration/matching_configuration.dart';

/// Immutable value-safe description of active request-matcher configuration.
///
/// Configured names, paths and matcher objects are deliberately represented by
/// counts only because their identifiers may themselves be confidential.
final class ReplayMatcherDescription {
  /// Captures value-safe facts from [configuration].
  factory ReplayMatcherDescription.fromConfiguration(
    MatchingConfiguration configuration,
  ) =>
      ReplayMatcherDescription._(
        selectedHeaderCount: configuration.includedHeaders.length,
        ignoredQueryParameterCount: configuration.ignoredQueryParameters.length,
        ignoredJsonLocationCount: configuration.ignoredJsonPointers.length,
        customComponentCount: configuration.customComponents.length,
      );

  const ReplayMatcherDescription._({
    required this.selectedHeaderCount,
    required this.ignoredQueryParameterCount,
    required this.ignoredJsonLocationCount,
    required this.customComponentCount,
  });

  /// Whether canonical HTTP method matching is active.
  bool get matchesMethod => true;

  /// Whether normalised URI matching is active.
  bool get matchesUri => true;

  /// Whether non-empty request body matching is active.
  bool get matchesNonEmptyBody => true;

  /// The number of selected header names without retaining those names.
  final int selectedHeaderCount;

  /// The number of query parameter values ignored during matching.
  final int ignoredQueryParameterCount;

  /// The number of exact JSON locations ignored during matching.
  final int ignoredJsonLocationCount;

  /// The number of additive custom components without retaining their names.
  final int customComponentCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayMatcherDescription &&
          selectedHeaderCount == other.selectedHeaderCount &&
          ignoredQueryParameterCount == other.ignoredQueryParameterCount &&
          ignoredJsonLocationCount == other.ignoredJsonLocationCount &&
          customComponentCount == other.customComponentCount;

  @override
  int get hashCode => Object.hash(
        selectedHeaderCount,
        ignoredQueryParameterCount,
        ignoredJsonLocationCount,
        customComponentCount,
      );
}
