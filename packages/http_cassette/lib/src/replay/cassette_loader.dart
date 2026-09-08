import '../cassette/cassette.dart';
import '../cassette/decoder.dart';
import '../cassette/name.dart';
import '../store/exception.dart';
import '../store/store.dart';
import 'decode_diagnostic.dart';
import 'loading_failure.dart';
import 'store_read_diagnostic.dart';

/// The outcome of loading and decoding one replay cassette.
sealed class ReplayCassetteLoadResult {
  const ReplayCassetteLoadResult._();

  /// Creates a successful result containing the decoded [cassette].
  const factory ReplayCassetteLoadResult.loaded(Cassette cassette) =
      ReplayCassetteLoaded._;

  /// Creates a result containing one safe loading [failure].
  const factory ReplayCassetteLoadResult.failed(
    ReplayCassetteLoadFailure failure,
  ) = ReplayCassetteLoadFailed._;
}

/// A successfully decoded replay cassette.
final class ReplayCassetteLoaded extends ReplayCassetteLoadResult {
  const ReplayCassetteLoaded._(this.cassette) : super._();

  /// The immutable cassette reconstructed from the store snapshot.
  final Cassette cassette;
}

/// An expected, safely projected replay loading failure.
final class ReplayCassetteLoadFailed extends ReplayCassetteLoadResult {
  const ReplayCassetteLoadFailed._(this.failure) : super._();

  /// Safe structured details of the failed store read or decode.
  final ReplayCassetteLoadFailure failure;
}

/// Loads and strictly decodes replay cassettes from one store.
final class ReplayCassetteLoader {
  /// Creates a loader backed by [store].
  const ReplayCassetteLoader(this.store);

  /// The store used for the single snapshot read and its decoding limit.
  final CassetteStore store;

  /// Reads and decodes the complete cassette identified by [cassetteName].
  ///
  /// Expected store and decoder failures are returned as safe typed results.
  /// Broken store contracts and unexpected exceptions propagate.
  Future<ReplayCassetteLoadResult> load(CassetteName cassetteName) async {
    try {
      final snapshot = await store.read(cassetteName);
      if (snapshot.name != cassetteName) {
        throw StateError(
          'A cassette store returned a snapshot for a different name.',
        );
      }
      return ReplayCassetteLoadResult.loaded(
        decodeCassetteV1(
          snapshot.bytes,
          maximumBytes: store.maximumBytes,
        ),
      );
    } on CassetteStoreException catch (failure) {
      if (failure.name != cassetteName) {
        throw StateError(
          'A cassette store reported a failure for a different name.',
        );
      }
      return ReplayCassetteLoadResult.failed(
        ReplayCassetteLoadFailure.storeRead(
          ReplayStoreReadDiagnostic.fromStoreFailure(failure),
        ),
      );
    } on CassetteDecodeException catch (failure) {
      return ReplayCassetteLoadResult.failed(
        ReplayCassetteLoadFailure.decode(
          ReplayCassetteDecodeDiagnostic.fromDecodeFailure(
            cassetteName: cassetteName,
            failure: failure,
          ),
        ),
      );
    }
  }
}
