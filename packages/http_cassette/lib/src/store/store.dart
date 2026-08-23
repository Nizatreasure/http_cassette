import '../cassette/name.dart';
import 'exception.dart';
import 'snapshot.dart';

/// A transport-neutral store for encoded safe cassette bytes.
///
/// Implementations must defensively copy byte input before completing a write.
/// Direct callers are responsible for supplying fully sanitised, validated and
/// encoded cassette bytes. Stores do not decode, match, sanitise or migrate
/// cassette content.
abstract interface class CassetteStore {
  /// Reports whether [name] currently exists.
  Future<bool> exists(CassetteName name);

  /// Reads one immutable snapshot for [name].
  ///
  /// Throws a not-found [CassetteStoreException] when [name] does not exist.
  Future<CassetteSnapshot> read(CassetteName name);

  /// Creates [name] from encoded [bytes] only when it is absent.
  ///
  /// Throws an already-exists [CassetteStoreException] rather than replacing
  /// existing content.
  Future<void> create(CassetteName name, List<int> bytes);

  /// Explicitly replaces existing [name] with encoded [bytes].
  ///
  /// Throws a not-found [CassetteStoreException] when [name] does not exist.
  Future<void> replace(CassetteName name, List<int> bytes);

  /// Replaces [snapshot] with encoded [bytes] only if its revision is current.
  ///
  /// Throws a revision-changed [CassetteStoreException] when the stored value
  /// changed after [snapshot] was read. A store without this capability throws
  /// an unsupported-operation [CassetteStoreException].
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  );
}
