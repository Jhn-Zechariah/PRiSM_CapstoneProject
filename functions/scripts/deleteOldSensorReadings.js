/**
 * One-time cleanup of sensor_readings_seconds documents written before the
 * ESP32 started adding `expireAt` (those are never removed by the TTL
 * policy, because they have no `expireAt` field).
 *
 * Deletes all second-level readings older than RETENTION_DAYS (7 days),
 * including any matching readings that already have expireAt.
 * sensor_readings_hourly is NOT touched.
 *
 * Cost: one read + one delete per removed document (one time only).
 *
 * Usage (from the functions/ folder, after `gcloud auth application-default login`):
 *   node scripts/deleteOldSensorReadings.js --limit 1000            -> dry run
 *   node scripts/deleteOldSensorReadings.js --limit 1000 --confirm  -> deletes at most 1000
 *   Omitting --limit applies no deletion cap.
 */
const { parseArgs } = require("node:util");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const PROJECT_ID = "prism-3cd2c";
const RETENTION_DAYS = 7;
const BATCH_SIZE = 500;

const app = initializeApp({ projectId: PROJECT_ID });
const db = getFirestore(app);

async function main() {
    const { values: { confirm, limit } } = parseArgs({
        options: {
            confirm: { type: "boolean" },
            limit: { type: "string" },
        },
    });
    const maxDeletes = limit === undefined ? Infinity : Number(limit);
    if (limit !== undefined && (!/^\d+$/.test(limit) || !Number.isSafeInteger(maxDeletes) || maxDeletes < 1)) {
        throw new Error("--limit must be a positive whole number.");
    }
    const cutoff = Timestamp.fromMillis(
        Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000
    );
    const query = db
        .collection("sensor_readings_seconds")
        .where("timestamp", "<", cutoff);

    // count() is billed at 1 read per 1,000 documents, so the dry run is cheap.
    const total = (await query.count().get()).data().count;
    console.log(`${total} reading(s) older than ${cutoff.toDate().toISOString()}`);

    if (!confirm) {
        console.log(`Dry run. With these options, --confirm would delete up to ${Math.min(total, maxDeletes)} reading(s).`);
        return;
    }

    let deleted = 0;
    while (deleted < maxDeletes) {
        // select() with no fields: only the document references are needed.
        const batchLimit = Math.min(BATCH_SIZE, maxDeletes - deleted);
        const snap = await query.orderBy("timestamp").select().limit(batchLimit).get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        deleted += snap.size;
        console.log(`Deleted ${deleted}/${Math.min(total, maxDeletes)}`);
    }
    console.log(`Done. Deleted ${deleted} reading(s).`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
