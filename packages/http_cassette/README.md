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

`CassetteName` validates portable slash-separated logical names. Stores will own
the physical path and `.json` suffix:

```dart
final cassetteName = CassetteName('checkout/expired-discount');
```

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

`CassetteOutcome` represents either a received response or a portable transport
failure. Caller cancellation and cassette-system failures are not outcomes:

```dart
final outcome = CassetteResponseOutcome(response);
```

`BodyLimits` provides measured byte limits for future bounded buffering:

| Body | Default |
| --- | ---: |
| Request | 2 MiB |
| Response | 5 MiB |

Both values require positive byte counts and may be overridden explicitly.
Buffering and limit enforcement are not implemented yet.

The internal matching foundation now normalises HTTP methods, URI origins,
paths and queries conservatively. Query-name order is ignored, while repeated
values retain their order. Headers are ignored unless explicitly selected;
selected values preserve order and compare after surrounding HTTP whitespace is
removed. Body comparison is not implemented yet. Adapters must supply
internationalised hosts in canonical ASCII form.

## Example

The example constructs foundational configuration and canonical HTTP values. It
also formats a structured missing-cassette diagnostic.

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.
