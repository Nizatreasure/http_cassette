import '../matching/exclusions.dart';
import '../model/headers.dart';
import '../model/outcome.dart';
import 'body_codec.dart';
import 'cassette.dart';
import 'interaction.dart';
import 'request_encoding.dart';

/// Projects [cassette] into the immutable, ordered V1 persistence schema.
///
/// The returned tree still contains lossless parsed JSON numbers. Converting
/// the tree into deterministic UTF-8 JSON is a separate encoder responsibility.
Map<String, Object?> projectCassetteSchemaV1(Cassette cassette) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      'schemaVersion': cassette.schemaVersion,
      'interactions': List<Object?>.unmodifiable(
        cassette.interactions.map(_projectInteraction),
      ),
    });

Map<String, Object?> _projectInteraction(CassetteInteraction interaction) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      'index': interaction.index,
      'request': _projectRequest(interaction),
      'outcome': _projectOutcome(interaction.outcome),
    });

Map<String, Object?> _projectRequest(CassetteInteraction interaction) {
  final request = interaction.request;
  final prepared = preparePersistedBody(request.headers, request.body);
  final exclusions = interaction.matchingExclusions.mergedWith(
    MatchingExclusions(headers: prepared.changedHeaderNames),
  );

  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'method': request.method,
    'uri': canonicalisePersistedRequestUri(request),
    'headers': _projectHeaders(prepared.headers),
    'body': _projectBody(prepared.body),
    'matchingExclusions': _projectExclusions(exclusions),
  });
}

Map<String, Object?> _projectOutcome(CassetteOutcome outcome) =>
    switch (outcome) {
      CassetteResponseOutcome() => _projectResponse(outcome),
      CassetteTransportFailure() => Map<String, Object?>.unmodifiable(
          <String, Object?>{
            'type': 'transportFailure',
            'category': outcome.category.name,
            'message': outcome.message,
          },
        ),
    };

Map<String, Object?> _projectResponse(CassetteResponseOutcome outcome) {
  final response = outcome.response;
  final prepared = preparePersistedBody(response.headers, response.body);

  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'type': 'response',
    'statusCode': response.statusCode,
    if (response.reasonPhrase case final reasonPhrase?)
      'reasonPhrase': reasonPhrase,
    'headers': _projectHeaders(prepared.headers),
    'body': _projectBody(prepared.body),
  });
}

Map<String, Object?> _projectHeaders(CassetteHeaders headers) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final name in headers.names)
        name: List<String>.unmodifiable(headers.values(name)!),
    });

Map<String, Object?> _projectBody(PersistedBody body) => switch (body) {
      PersistedEmptyBody() => Map<String, Object?>.unmodifiable(
          <String, Object?>{'encoding': 'empty'},
        ),
      PersistedJsonBody() => Map<String, Object?>.unmodifiable(
          <String, Object?>{
            'encoding': 'json',
            'content': body.content,
          },
        ),
      PersistedTextBody() => Map<String, Object?>.unmodifiable(
          <String, Object?>{
            'encoding': 'text',
            'content': body.content,
          },
        ),
      PersistedBase64Body() => Map<String, Object?>.unmodifiable(
          <String, Object?>{
            'encoding': 'base64',
            'content': body.content,
          },
        ),
    };

Map<String, Object?> _projectExclusions(MatchingExclusions exclusions) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      'uriUserInformation': exclusions.uriUserInformation,
      'body': exclusions.body,
      'headers': List<String>.unmodifiable(exclusions.headers),
      'queryParameters': List<String>.unmodifiable(
        exclusions.queryParameters,
      ),
      'jsonPointers': List<String>.unmodifiable(exclusions.jsonPointers),
    });
