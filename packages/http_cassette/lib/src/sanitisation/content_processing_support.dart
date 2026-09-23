import 'content_processing_support_stub.dart'
    if (dart.library.io) 'content_processing_support_io.dart' as platform;

/// Whether this platform supports HTTP Cassette's gzip body processing.
bool get supportsGzipContentProcessing =>
    platform.supportsGzipContentProcessing;
