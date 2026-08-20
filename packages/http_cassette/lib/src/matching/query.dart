import 'difference.dart';
import 'exclusions.dart';
import 'uri_component.dart';

/// An immutable, deterministic representation of an encoded URI query.
final class NormalisedQuery {
  /// Parses and normalises the query from [uri].
  ///
  /// Values selected by [exclusions] are omitted while their names,
  /// multiplicity, order and equals-sign state remain significant.
  factory NormalisedQuery.fromUri(
    Uri uri, {
    MatchingExclusions exclusions = MatchingExclusions.none,
  }) {
    if (uri.query.isEmpty) {
      return const NormalisedQuery._(<NormalisedQueryGroup>[]);
    }

    final grouped = <String, List<NormalisedQueryValue>>{};

    for (final field in uri.query.split('&')) {
      final equalsIndex = field.indexOf('=');
      final hasEquals = equalsIndex >= 0;
      final encodedName = hasEquals ? field.substring(0, equalsIndex) : field;
      final name = normaliseUriComponent(encodedName);
      final encodedValue = hasEquals ? field.substring(equalsIndex + 1) : '';
      final isExcluded = exclusions.queryParameters.contains(name);
      final value = NormalisedQueryValue._(
        value: isExcluded ? null : normaliseUriComponent(encodedValue),
        hasEquals: hasEquals,
        isExcluded: isExcluded,
      );
      (grouped[name] ??= <NormalisedQueryValue>[]).add(value);
    }

    final names = grouped.keys.toList()..sort();
    return NormalisedQuery._(
      List<NormalisedQueryGroup>.unmodifiable(
        names.map(
          (name) => NormalisedQueryGroup._(
            name: name,
            values: List<NormalisedQueryValue>.unmodifiable(grouped[name]!),
          ),
        ),
      ),
    );
  }

  const NormalisedQuery._(this.groups);

  /// Query groups sorted by normalised name.
  final List<NormalisedQueryGroup> groups;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedQuery && _listsEqual(groups, other.groups);

  @override
  int get hashCode => Object.hashAll(groups);
}

/// Compares normalised queries without retaining parameter values.
BoundedMatchDifferences compareNormalisedQueries(
  NormalisedQuery expected,
  NormalisedQuery actual, {
  int maximumRetained = MatchDifferenceCollector.defaultMaximumRetained,
}) {
  final collector = MatchDifferenceCollector(maximumRetained: maximumRetained);
  final expectedByName = <String, NormalisedQueryGroup>{
    for (final group in expected.groups) group.name: group,
  };
  final actualByName = <String, NormalisedQueryGroup>{
    for (final group in actual.groups) group.name: group,
  };
  final names = <String>{...expectedByName.keys, ...actualByName.keys}.toList()
    ..sort();

  for (final name in names) {
    final expectedGroup = expectedByName[name];
    final actualGroup = actualByName[name];
    if (expectedGroup == null) {
      collector.add(
        MatchDifference(kind: MatchDifferenceKind.extra, location: name),
      );
      continue;
    }
    if (actualGroup == null) {
      collector.add(
        MatchDifference(kind: MatchDifferenceKind.missing, location: name),
      );
      continue;
    }

    if (expectedGroup.values.length != actualGroup.values.length) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.differentMultiplicity,
          location: name,
        ),
      );
    } else if (!_listsEqual(expectedGroup.values, actualGroup.values) &&
        _containEquivalentValues(expectedGroup.values, actualGroup.values)) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.differentOrder,
          location: name,
        ),
      );
      continue;
    }

    final sharedLength = expectedGroup.values.length < actualGroup.values.length
        ? expectedGroup.values.length
        : actualGroup.values.length;
    for (var index = 0; index < sharedLength; index += 1) {
      final expectedValue = expectedGroup.values[index];
      final actualValue = actualGroup.values[index];
      if (expectedValue.hasEquals != actualValue.hasEquals) {
        collector.add(
          MatchDifference(
            kind: MatchDifferenceKind.differentType,
            location: '$name[$index]',
          ),
        );
      } else if (expectedValue != actualValue) {
        collector.add(
          MatchDifference(
            kind: MatchDifferenceKind.differentValue,
            location: '$name[$index]',
          ),
        );
      }
    }
    for (var index = sharedLength;
        index < expectedGroup.values.length;
        index += 1) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.missing,
          location: '$name[$index]',
        ),
      );
    }
    for (var index = sharedLength;
        index < actualGroup.values.length;
        index += 1) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.extra,
          location: '$name[$index]',
        ),
      );
    }
  }
  return collector.build();
}

/// Every occurrence of one normalised query name.
final class NormalisedQueryGroup {
  const NormalisedQueryGroup._({
    required this.name,
    required this.values,
  });

  /// The conservatively normalised encoded name.
  final String name;

  /// Occurrences in their original relative order.
  final List<NormalisedQueryValue> values;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedQueryGroup &&
          name == other.name &&
          _listsEqual(values, other.values);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(values));
}

/// One normalised query value and its equals-sign state.
final class NormalisedQueryValue {
  const NormalisedQueryValue._({
    required this.value,
    required this.hasEquals,
    required this.isExcluded,
  });

  /// The conservatively normalised encoded value, or `null` when excluded.
  final String? value;

  /// Whether the original occurrence contained `=`.
  final bool hasEquals;

  /// Whether the original value was excluded from matching.
  final bool isExcluded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedQueryValue &&
          value == other.value &&
          hasEquals == other.hasEquals &&
          isExcluded == other.isExcluded;

  @override
  int get hashCode => Object.hash(value, hasEquals, isExcluded);
}

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool _containEquivalentValues(
  List<NormalisedQueryValue> expected,
  List<NormalisedQueryValue> actual,
) {
  final unmatched = List<NormalisedQueryValue>.of(actual);
  for (final value in expected) {
    final index = unmatched.indexOf(value);
    if (index == -1) {
      return false;
    }
    unmatched.removeAt(index);
  }
  return unmatched.isEmpty;
}
