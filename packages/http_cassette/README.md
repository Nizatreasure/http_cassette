# http_cassette

`http_cassette` is the planned transport-neutral core of HTTP Cassette, a Dart
package family for recording and replaying HTTP interactions in tests.

This package is under active development. It currently provides foundational
canonical HTTP values and safe structured diagnostics. It does not yet record,
replay, match, sanitise or persist HTTP interactions.

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

`CassetteRequest` and `CassetteResponse` provide immutable canonical messages
with defensively protected byte bodies:

```dart
final request = CassetteRequest(
  method: 'GET',
  uri: Uri.parse('https://api.example.test/profile'),
  headers: headers,
);
```

## Example

The example constructs canonical request and response values and formats a
structured missing-cassette diagnostic.

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.
