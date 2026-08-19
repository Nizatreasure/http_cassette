# HTTP Cassette

HTTP Cassette is a planned family of pure-Dart packages for recording and
replaying HTTP interactions in tests.

This repository currently contains only the package scaffolds. Recording,
replay, matching, sanitisation, persistence and transport adapters are not yet
implemented, and no public API is available.

## Packages

- `http_cassette` will contain the transport-neutral core.
- `http_cassette_dio` will contain the Dio integration.
- `http_cassette_http` will contain the `package:http` integration.

The three packages use a native Dart pub workspace while remaining structured
for independent publication.

## Development

The workspace requires Dart 3.6 or later.

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test packages/http_cassette/test
dart test packages/http_cassette_dio/test
dart test packages/http_cassette_http/test
```

## Licence

HTTP Cassette is licensed under the BSD 3-Clause License.
