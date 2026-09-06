# HTTP Cassette

HTTP Cassette records HTTP requests and their outcomes, then replays them without contacting the original server. It is designed for deterministic Dart tests and for capturing repeatable scenarios while developing an application.

The project is pure Dart and does not depend on Flutter. Its core is independent of any HTTP client, with official integrations for Dio and `package:http`.

## Packages

Choose the integration used by your application:

| Package | Purpose |
| --- | --- |
| [`http_cassette`](packages/http_cassette) | The transport-neutral engine, configuration, matching, sanitisation, diagnostics, cassette format, and storage. Use it directly when building a custom adapter. |
| [`http_cassette_dio`](packages/http_cassette_dio) | Installs HTTP Cassette at Dio's `HttpClientAdapter` boundary. |
| [`http_cassette_http`](packages/http_cassette_http) | Wraps a `package:http` client with `CassetteHttpClient`. |

Applications normally depend on `http_cassette` and one adapter package.

## How it works

A `CassetteEngine` controls one explicit recording or replay session at a time. The installed adapter uses that same engine.

During recording, the adapter sends the real request, converts the completed response or transport failure into a portable form, sanitises the interaction, and adds it to the active cassette. Closing the session writes the complete cassette.

During replay, the engine matches each incoming request against the recorded interactions. A matching outcome is returned through the adapter without a network call. A missing cassette, unmatched request, or exhausted interaction fails safely and never falls back to the real transport.

When no session is active, an installed adapter passes traffic to its wrapped transport normally.

## Main guarantees

- Recording is explicit.
- Active replay never accesses the network.
- Requests are matched deterministically.
- Recording is sanitised before persistence.
- Diagnostic messages do not reveal sanitised values.
- Cassette bodies and complete cassette files have configurable size limits.
- Dio and `package:http` use the same portable cassette format.

## Storage

The core package provides:

- `MemoryCassetteStore` for isolate-local, in-memory cassettes;
- `FileCassetteStore` for bounded JSON cassette files on platforms which support `dart:io`;
- `CassetteStore` for custom storage implementations.

Use logical cassette names such as `checkout/declined-card`. The file store owns the root directory and `.json` suffix and prevents a logical name from escaping its configured root.

## Security

Built-in sanitisation removes common credential-shaped headers, query parameters, and JSON values before a recording is stored. Applications which handle domain-specific personal or confidential data must add their own rules.

Automatic sanitisation reduces risk but cannot prove that a cassette is safe to share. Review every generated cassette before committing or publishing it. Never store real credentials, access tokens, or private customer traffic in the repository.

## Portability and limitations

Cassettes contain portable HTTP information: method, normalised URI, visible headers, body bytes, response status and reason phrase, or a portable transport failure. They do not reproduce client-specific state such as progress events, connection objects, redirect history, Dio `extra`, stream timing, or original chunk boundaries.

Active request and response streams are buffered within configured limits. Endless streams, server-sent events, exact stream timing, and semantic multipart matching are outside the V1 contract.

See each package README for installation, setup, examples, client-specific behaviour, and failure handling.

## Repository development

The workspace requires Dart 3.6 or later.

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test packages/http_cassette/test
dart test packages/http_cassette_dio/test
dart test packages/http_cassette_http/test
dart run packages/http_cassette/example/http_cassette_example.dart
dart run packages/http_cassette_dio/example/http_cassette_dio_example.dart
dart run packages/http_cassette_http/example/http_cassette_http_example.dart
```

## Issues

Report defects and documentation problems through the [GitHub issue tracker](https://github.com/Nizatreasure/http_cassette/issues). Do not include credentials, unsanitised recordings, or private HTTP traffic in an issue.

## Licence

HTTP Cassette is available under the BSD 3-Clause License. See [`LICENSE`](LICENSE).
