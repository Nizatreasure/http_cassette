import '../matching/normalisation.dart';
import '../matching/query.dart';
import '../model/http_message.dart';

/// Returns the deterministic V1 URI string for [request].
String canonicalisePersistedRequestUri(CassetteRequest request) {
  final target = NormalisedRequestTarget.fromRequest(request);
  final query = NormalisedQuery.fromUri(request.uri);
  final output = StringBuffer()
    ..write(target.scheme)
    ..write('://');

  if (target.userInformation case final userInformation?) {
    output
      ..write(userInformation)
      ..write('@');
  }

  if (target.host.contains(':')) {
    output
      ..write('[')
      ..write(target.host)
      ..write(']');
  } else {
    output.write(target.host);
  }

  if (target.port case final port?) {
    output
      ..write(':')
      ..write(port);
  }
  output.write(target.path);

  if (query.groups.isNotEmpty) {
    output.write('?');
    var first = true;
    for (final group in query.groups) {
      for (final value in group.values) {
        if (!first) {
          output.write('&');
        }
        first = false;
        output.write(group.name);
        if (value.hasEquals) {
          output
            ..write('=')
            ..write(value.value!);
        }
      }
    }
  }

  return output.toString();
}
