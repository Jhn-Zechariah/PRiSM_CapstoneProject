# Firestore security rules review

**Status:** `firestore.rules` is a **proposal**. It is **not** referenced from `firebase.json`, so
`firebase deploy` will not push it. The proposed rules pass 30 checks on the local emulator
(`sh tests_firestore_rules/test.sh`).

## 1. What could be reviewed

- **No rules file exists in the repository, on any branch** (REPO_AUDIT.md H5). The rules deployed
  on `prism-3cd2c` could not be read from here: there is no console or CLI access with credentials.
  **The current rules are therefore unverified.**
- The proposal was built from the reads and writes the code actually makes. The table below cites
  where each pattern comes from.

| Collection | Who reads / writes today | Evidence |
|---|---|---|
| `admins/{uid}` | own doc (profile, `fcmToken`, `notificationPreferences`, `iotThresholds`) | `firestore_profile_repo.dart`, `profile_cubit.dart:115` |
| `pigs` + `weight_history`, `feeding_records`, `medicine_intakes` | owner (`userId`). A pig and its first weights are created in one transaction | `firestore_pig_repo.dart:43-80` |
| `medicines` + `medicine_stock` | owner | `firestore_medicine_repo.dart` |
| `sensor_readings_seconds`, `sensor_readings_hourly`, `live_sensor`, `sprinkler_logs` | ESP32 writes, app reads | monitoring screens, `Dashboard_Screen.dart` |
| `sprinkler_command/pending` | app writes `{state}`; ESP32 also flips it | `Dashboard_Screen.dart:1561`, `:468` |
| `sprinkler_settings/config` | app merge-writes 4 keys; ESP32 reads | `IoTControlsDialog.dart:189-197` |
| `sprinkler_state/latest`, `sensor_memory/latest` | app writes UI state | `Dashboard_Screen.dart:530-705` |
| `assessment_results` (new) | app creates its own results | `lib/features/assessment/data/firestore_assessment_store.dart` |
| `sensor_corrections` (new) | admin only (normally via the Admin SDK) | `prism-ml2.0/pipeline/corrections.py` |

## 2. Weaknesses found

1. **Unreviewable rules.** None are in version control, so nobody can review or reproduce them.
2. **Cross-user read in the app.** `Dashboard_Screen.dart` ran `collectionGroup('medicine_intakes').where('category', ...)`
   with no `userId` filter. That reads every user's intakes, and it only works if rules let anyone read
   them all. **Fixed:** the query now filters on `userId`. That is the same index
   `firestore_medicine_repo.dart:30` already uses, and the category is checked in the app, so no new
   index is needed. Under the proposed rules the old query is denied (tested).
   - Behavior change: legacy intakes without a `userId` field no longer appear on the dashboard.
3. **One farm shared by every account.**
   - The sensor and sprinkler documents are global, and sign-up is open (`firebase_auth_repo.dart:80`).
   - Any signed-in account, including a stranger who registers, can read the sensors and toggle the
     sprinkler.
   - Fixing this properly needs a farm-membership model (for example `farms/{farmId}/members`). That
     changes the data model and the firmware paths, so it is **left for your decision**. The
     proposal at least limits sprinkler writes to the exact payloads the app sends.
4. **Raw observations are not protected from edits.** Nothing stops a client from rewriting
   `sensor_readings_seconds`. The proposal makes them create-only, for the device only.
5. **Device identity is unknown.** How the ESP32 authenticates (anonymous, email/password or custom
   token) cannot be seen without the firmware. The proposal uses the placeholder `isDevice()` =
   custom claim `device: true`. **If this is wrong, deploying stops sensor logging.**
6. **Alerts go to every account.** `onLiveSensorUpdate` loops over all `admins` (`functions/index.js:306`),
   so every registered account gets this farm's threshold alerts. This is not a rules issue, but it
   comes from the same missing farm-membership model.
7. **"admins" is not a role.** The collection holds every user. The proposal and the API therefore
   use a custom claim (`role: "admin"`), granted server-side with `python -m app.admin_claims grant <uid>`.

## 3. What the proposal changes (least privilege)

- **Owner-only:** pigs, their subcollections, medicines and the user's own doc. Child writes use
  `getAfter()`, so the `addPig` transaction keeps working (tested).
- **Raw sensor observations:** signed-in users can read; only the device can create; nobody can
  update or delete.
- **Sprinkler control:** behavior is unchanged.
  - `sprinkler_command` accepts only `{state: "on" | "off"}`.
  - `sprinkler_settings` saves may change only the 4 keys the app writes. This is merge-safe:
    fields the device keeps in that doc are left alone.
- **`assessment_results`:**
  - A user can create only their own results, with `origin == "api"` and the required fields.
  - Results can never be updated or deleted.
- **`sensor_corrections`:** admin claim only, append-only.
- **Everything else:** denied.

## 4. Before deploying

1. Export the live rules (Firebase console → Firestore → Rules) and diff them against `firestore.rules`.
2. Confirm the ESP32 sign-in method and fix `isDevice()`.
   - If the ESP32 uses a dedicated Firebase account, give that account the `device` claim (Admin SDK), or
   - compare `request.auth.uid` to that account's uid.
3. Run `sh tests_firestore_rules/test.sh`.
4. Add `"firestore": {"rules": "firestore.rules"}` to `firebase.json`. Then deploy with
   `firebase deploy --only firestore:rules --project prism-3cd2c`. Pass `--project` explicitly:
   `.firebaserc` still points at the old project.
5. Watch the ESP32 logs and the app for permission-denied errors right after deploying.
