# Account cache policy

Only Firebase Authentication UID `QaXqv3SX9YfdzRpyMbJXGYjxMnw1` may reuse cached application data. Change `AccountCachePolicy.designatedUid` in `lib/core/services/account_cache_policy.dart` to designate another account.

Firestore persistence remains enabled. Use `getForAccount()` and `snapshotsForAccount()` for application reads: other accounts require server reads and suppress local snapshot events. Explicit server-only sensor reads remain server-only for every account. Backend access permissions are separate from this client-side display policy.

Feeding and medicine caches are gated by the policy. Sensor chart buffers reset when accounts change and on screen re-entry for other accounts. Only the designated account can persist/restore chart preferences or save/restore sensor memory. Chart preference keys include the designated UID; legacy unscoped chart preferences are ignored. Current screen data and pagination state remain available while viewing the screen.

## Verification

Run `flutter test test/core/services/account_cache_policy_test.dart`.

On a device:
1. Sign in with the designated account, open data screens while online, then reopen them offline. Its cached data should remain available.
2. Sign out and sign in as another account while online. It should load fresh server data.
3. Take that account offline, leave and reopen data screens. It must not restore the designated account's cached data. Firestore server reads may show the existing loading/error UI while offline; current screen data is not blanked just because connectivity changes.
4. Switch back to the designated account. Its cache access should return.
5. Repeat with app restart and both email/password and Google sign-in.

The automated policy tests do not replace these device checks.
