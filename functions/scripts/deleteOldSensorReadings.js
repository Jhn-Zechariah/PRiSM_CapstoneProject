/**
 * One-time cleanup of sensor_readings_seconds documents written before the
 * ESP32 started adding `expireAt` (those are never removed by the TTL
 * policy, because they have no `expireAt` field).
 *
 * Deletes readings older than RETENTION_DAYS (same 7 days as the ESP32's
 * SECONDS_RETENTION_DAYS). sensor_readings_hourly is NOT touched.
 *
 * Cost: one read + one delete per removed document (one time only).
 *
 * Usage (from the functions/ folder, after `gcloud auth application-default login`):
 *   node scripts/deleteOldSensorReadings.js            -> dry run, only counts
 *   node scripts/deleteOldSensorReadings.js --confirm  -> deletes
 */
const admin = require("firebase-admin");

const PROJECT_ID = "prism-3cd2c";
const RETENTION_DAYS = 7;
const BATCH_SIZE = 500;

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function main() {
    const confirm = process.argv.includes("--confirm");
    const cutoff = admin.firestore.Timestamp.fromMillis(
        Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000
    );
    const query = db
        .collection("sensor_readings_seconds")
        .where("timestamp", "<", cutoff);

    // count() is billed at 1 read per 1,000 documents, so the dry run is cheap.
    const total = (await query.count().get()).data().count;
    console.log(`${total} reading(s) older than ${cutoff.toDate().toISOString()}`);

    if (!confirm) {
        console.log("Dry run. Re-run with --confirm to delete them.");
        return;
    }

    let deleted = 0;
    while (true) {
        // select() with no fields: only the document references are needed.
        const snap = await query.select().limit(BATCH_SIZE).get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        deleted += snap.size;
        console.log(`Deleted ${deleted}/${total}`);
    }
    console.log("Done.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
