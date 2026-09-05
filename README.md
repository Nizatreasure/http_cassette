# HTTP Cassette

HTTP Cassette is a family of pure-Dart packages for recording and replaying
HTTP interactions deterministically without unexpected network access.

The transport-neutral core and the Dio and `package:http` adapters are under
active development. Recording, replay, matching, sanitisation and memory and
file storage are implemented, but the packages are not yet ready for
publication.

## Packages

- `http_cassette` contains the transport-neutral engine and policies.
- `http_cassette_dio` connects Dio at its transport-adapter boundary.
- `http_cassette_http` provides a `package:http` client wrapper.

The three packages use a native Dart pub workspace while remaining structured
for independent publication.

## Adapter portability

Both official adapters use the same canonical cassette format. Contract tests
verify equivalent requests, successful responses and the common portable
transport-failure representation. A successful interaction recorded through
either adapter can be replayed through the other without calling its wrapped
transport.

Portable cassette data includes the HTTP method, normalised URI, visible
headers, body bytes, response status and reason phrase, and portable transport
failure details. Client-only behaviour is not portable: stream chunks and
timing, progress events, redirect history, connection state, Dio `extra`, and
custom `package:http` request-subclass state are not stored.

Portability is limited by what each client exposes. In particular,
`package:http` represents each request header as one string, so earlier
repeated request-header field lines cannot be recovered. Use canonical HTTP
features when a cassette must move between transports.

## Development

The workspace requires Dart 3.6 or later.

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test packages/http_cassette/test
dart test packages/http_cassette_dio/test
dart test packages/http_cassette_http/test
```

## Licence

HTTP Cassette is licensed under the BSD 3-Clause License.
