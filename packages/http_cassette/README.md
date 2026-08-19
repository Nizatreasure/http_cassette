# http_cassette

`http_cassette` is the planned transport-neutral core of HTTP Cassette, a Dart
package family for recording and replaying HTTP interactions in tests.

This package is under active development. It currently provides only the safe,
structured diagnostic foundations required by later behaviour. It does not yet
record, replay, match, sanitise or persist HTTP interactions.

## Installation

The package is not ready for use or publication. During development in this
workspace, it can be resolved with `dart pub get` from the repository root.

## Current API

`CassetteDiagnostic` carries a stable category, concise safe summary and network
access status. `CassetteException` carries that structured diagnostic without
requiring consumers to parse exception text.

Diagnostics provide deterministic plain-text formatting without logging
automatically:

```dart
final text = diagnostic.format();
```

`CassetteHeaders` provides immutable, transport-neutral HTTP fields with
case-insensitive lookup and ordered repeated values:

```dart
final headers = CassetteHeaders(<String, Iterable<String>>{
  'Accept': <String>['application/json'],
});
```

## Example

The example constructs canonical headers and formats a structured
missing-cassette diagnostic.

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.
