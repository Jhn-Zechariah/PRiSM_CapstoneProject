import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/services/account_cache_policy.dart';

void main() {
  const owner = 'QaXqv3SX9YfdzRpyMbJXGYjxMnw1';
  const other = 'another-account';

  test('only the designated UID can use cached data', () {
    expect(AccountCachePolicy.allowsUid(owner), isTrue);
    expect(AccountCachePolicy.allowsUid(other), isFalse);
    expect(AccountCachePolicy.allowsUid(null), isFalse);
    expect(AccountCachePolicy.allowsUid(''), isFalse);
    expect(AccountCachePolicy.allowsUid(owner.toLowerCase()), isFalse);
  });

  test('other accounts cannot request a cache-only read or fallback', () {
    for (final uid in [other, null]) {
      for (final source in Source.values) {
        expect(
          AccountCachePolicy.optionsForUid(uid, GetOptions(source: source)).source,
          Source.server,
        );
      }
      expect(AccountCachePolicy.optionsForUid(uid).source, Source.server);
    }
  });

  test('owner keeps cache access and explicit live-only reads', () {
    for (final source in Source.values) {
      expect(
        AccountCachePolicy.optionsForUid(owner, GetOptions(source: source)).source,
        source,
      );
    }
    expect(AccountCachePolicy.optionsForUid(owner).source, Source.serverAndCache);
  });

  test('cache snapshot is hidden from other accounts; server confirmation passes', () {
    for (final uid in [owner, other]) {
      expect(AccountCachePolicy.acceptsSnapshot(
        requestUid: uid, activeUid: uid, isFromCache: true,
      ), uid == owner);
      expect(AccountCachePolicy.acceptsSnapshot(
        requestUid: uid, activeUid: uid, isFromCache: false,
      ), isTrue);
    }
  });

  test('late snapshots from a previous account are discarded', () {
    for (final cached in [true, false]) {
      expect(AccountCachePolicy.acceptsSnapshot(
        requestUid: owner, activeUid: other, isFromCache: cached,
      ), isFalse);
      expect(AccountCachePolicy.acceptsSnapshot(
        requestUid: other, activeUid: owner, isFromCache: cached,
      ), isFalse);
      expect(AccountCachePolicy.acceptsSnapshot(
        requestUid: owner, activeUid: null, isFromCache: cached,
      ), isFalse);
    }
  });
}
