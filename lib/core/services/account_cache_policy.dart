import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controls reuse of local data, independently of backend access permissions.
class AccountCachePolicy {
  static const designatedUid = 'QaXqv3SX9YfdzRpyMbJXGYjxMnw1';

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
  static bool allowsUid(String? uid) => uid == designatedUid;
  static bool get canUseCache => allowsUid(currentUid);

  static GetOptions optionsForUid(String? uid, [GetOptions? requested]) =>
      allowsUid(uid)
          ? (requested ?? const GetOptions())
          : const GetOptions(source: Source.server);

  static bool acceptsSnapshot({
    required String? requestUid,
    required String? activeUid,
    required bool isFromCache,
  }) => requestUid == activeUid && (allowsUid(activeUid) || !isFromCache);

  static void checkSession(String? uid) {
    if (uid != currentUid) {
      throw StateError('Account changed while loading data. Please retry.');
    }
  }
}

extension AccountQueryReads<T extends Object?> on Query<T> {
  Future<QuerySnapshot<T>> getForAccount([GetOptions? options]) async {
    final uid = AccountCachePolicy.currentUid;
    final result = await get(AccountCachePolicy.optionsForUid(uid, options));
    AccountCachePolicy.checkSession(uid);
    return result;
  }

  Stream<QuerySnapshot<T>> snapshotsForAccount({
    bool includeMetadataChanges = false,
  }) {
    final uid = AccountCachePolicy.currentUid;
    // Metadata events let a server-confirmed snapshot through even when its
    // documents equal the initial (suppressed) local snapshot.
    return snapshots(includeMetadataChanges: true).where((snapshot) =>
        AccountCachePolicy.acceptsSnapshot(
          requestUid: uid,
          activeUid: AccountCachePolicy.currentUid,
          isFromCache: snapshot.metadata.isFromCache,
        ));
  }
}

extension AccountDocumentReads<T extends Object?> on DocumentReference<T> {
  Future<DocumentSnapshot<T>> getForAccount([GetOptions? options]) async {
    final uid = AccountCachePolicy.currentUid;
    final result = await get(AccountCachePolicy.optionsForUid(uid, options));
    AccountCachePolicy.checkSession(uid);
    return result;
  }

  Stream<DocumentSnapshot<T>> snapshotsForAccount({
    bool includeMetadataChanges = false,
  }) {
    final uid = AccountCachePolicy.currentUid;
    return snapshots(includeMetadataChanges: true).where((snapshot) =>
        AccountCachePolicy.acceptsSnapshot(
          requestUid: uid,
          activeUid: AccountCachePolicy.currentUid,
          isFromCache: snapshot.metadata.isFromCache,
        ));
  }
}
