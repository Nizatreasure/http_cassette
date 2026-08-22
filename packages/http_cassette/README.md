# http_cassette

`http_cassette` is the planned transport-neutral core of HTTP Cassette, a Dart
package family for recording and replaying HTTP interactions in tests.

This package is under active development. It currently provides foundational
canonical HTTP values and safe structured diagnostics. It does not yet record,
replay, sanitise or persist HTTP interactions, and the matcher is not yet
exposed as an operational engine.

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

`MatchingConfiguration` selects headers and exact query or JSON values to
ignore. Method, URI and non-empty-body matching remain fixed:

```dart
final matching = MatchingConfiguration(
  includedHeaders: <String>{'accept'},
  ignoredQueryParameters: <String>{'request_id'},
  ignoredJsonPointers: <String>{'/metadata/generated_at'},
);
```

The internal matching foundation now normalises HTTP methods, URI origins,
paths and queries conservatively. Query-name order is ignored, while repeated
values retain their order. Headers are ignored unless explicitly selected;
selected values preserve order and compare after surrounding HTTP whitespace is
removed. JSON bodies are classified from `application/json` and structured
`+json` content types, then parsed strictly as UTF-8 with duplicate object
members rejected. Parsed JSON can be compared structurally: object order is
ignored, array order is preserved and equivalent number spellings match without
losing precision. This remains an internal matching foundation; full request
comparison now composes these components without replay state. Opaque bodies
compare as exact bytes; differences retain only safe length, empty-state and
first-offset facts. Adapters must supply internationalised hosts in canonical
ASCII form. Matching exclusions validate header names and exact JSON Pointers.
Excluded query values retain their parameter names, multiplicity, order and
equals-sign state. A whole-body exclusion is available for custom sanitisers
that replace an opaque body or the complete body structure. It ignores the body
value only: an empty body still does not match a non-empty body. Use exact JSON
Pointers when only selected JSON locations changed.

The transport-neutral custom matcher contract supports additional safe matching
requirements. Registered components run after the built-in components in their
configuration order and contribute to matching eligibility and closest-match
ranking. Custom components cannot replace built-in matching in the current API.

`SanitisationConfiguration` enables fixed rules for common credential headers,
query parameters and JSON member names. Projects may add exact header names,
query names, JSON member names and JSON Pointers. This configuration is
available now, but the sanitisation pipeline is not implemented yet. These
defaults reduce risk; they cannot guarantee that a future cassette is safe to
commit, so generated cassettes will still require review.

Built-in rules can be disabled only with the conspicuously named
`SanitisationConfiguration.unsafeWithoutBuiltIns()` constructor. Recording with
that configuration may persist raw credentials and personal data. It is not an
ordinary setup option and is not used by the package example.

The internal sanitisation foundation now replaces complete values for
`authorization`, `cookie`, `proxy-authorization`, `set-cookie`, `x-api-key`,
`api-key`, `x-auth-token`, `x-csrf-token` and `x-xsrf-token`, plus configured
exact header names. Repeated values retain their count. It also replaces every
present value of common credential-shaped query parameters and configured exact
query names while preserving names, order, multiplicity, and missing versus
empty values. URI user information is replaced as one complete value. The
internal request-field result carries matching exclusions for every changed
location. The internal JSON foundation recursively sanitises exact sensitive
member names and exact RFC 6901 locations while retaining object and array
shape. Body composition and the recording pipeline are not implemented yet.

### Choosing JSON sanitisation rules

An additional JSON member name applies at every object depth and is matched
case-insensitively. For example, adding `customerReference` sanitises every
member with that name, including members inside arrays. Use this form only when
every occurrence is sensitive.

An RFC 6901 JSON Pointer applies to one exact, case-sensitive location. For
example, `/credentials/code` sanitises that value without changing
`/metadata/code`. Use a pointer when the same member name is sensitive in one
part of a document but safe elsewhere. Pointer tokens use RFC 6901 escaping:
`~1` represents `/` and `~0` represents `~`.

Built-in credential-shaped names such as `token`, `password` and
`authorization` deliberately apply everywhere as a secure default. A selected
object or array keeps its keys, length and nesting while all scalar descendants
are replaced. That remaining shape can itself be sensitive, so projects should
use a future custom body sanitiser when the structure must also be hidden.

Automatic sanitisation reduces risk but cannot recognise every secret or item
of personal information. Add project rules for domain-specific data and review
every generated cassette before committing it.

A body that declares a JSON media type must be valid UTF-8 JSON without
duplicate object member names before built-in sanitisation can inspect it. The
internal body sanitisation foundation fails safely rather than retaining
uninspectable claimed JSON. Non-JSON bodies are opaque to built-in sanitisation
and remain unchanged; projects must use a future custom body sanitiser when
those bytes may contain sensitive data. The explicit unsafe no-built-ins
configuration also disables this claimed-JSON inspection guarantee. Integration
with the recording pipeline is not implemented yet. The internal composition
layer now applies these built-ins to complete canonical requests and responses,
and carries every changed request location into matching exclusions.

### Custom sanitiser contracts

`RequestSanitiser` and `ResponseSanitiser` are transport-neutral extension
contracts. A request sanitiser returns a `SanitisedRequest` containing valid
canonical data and a validated `MatchingExclusions` value for every changed
location that affects matching. A response sanitiser returns a valid canonical
response. Implementations must be deterministic and must not log their raw
input. If a request sanitiser replaces the complete body, it may report a
whole-body exclusion; body presence remains significant.

Custom sanitisers may be registered through `SanitisationConfiguration` and are
retained in explicit order. Registration is immutable and defensively copied.
The unsafe no-built-ins constructor does not suppress custom sanitisers.
Custom request sanitisers now execute internally in that order, with each output
feeding the next. Each changed request is checked against the exclusions
reported by that sanitiser; incomplete exclusions or changes to fixed request
identity fail without retaining changed values in diagnostics. Response
sanitisers also execute internally in registration order, with each canonical
output feeding the next. Responses need no matching exclusions because they do
not select recorded interactions. The complete internal pipeline now runs each
custom chain first and the built-in rules last, then unions custom and built-in
request exclusions. The explicit unsafe no-built-ins policy still runs custom
sanitisers. Recording integration is not implemented yet.

## Example

The example constructs body and matching configuration with canonical HTTP
values. It also formats a structured missing-cassette diagnostic.

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.
