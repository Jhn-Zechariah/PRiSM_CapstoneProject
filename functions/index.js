const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

/**
 * Sends a single FCM push to a user, swallowing errors per-send so that
 * one bad/stale token never aborts processing for other users.
 */
async function safeSend(userId, payload) {
    try {
        await admin.messaging().send(payload);
    } catch (error) {
        logger.error(`Failed to send notification to user ${userId}:`, error);
    }
}

/**
 * Fetches an admin doc, using an in-memory cache map to avoid re-fetching
 * the same user document multiple times within a single function run.
 */
async function getCachedAdmin(firestore, cache, userId) {
    if (!userId) return null;
    if (cache.has(userId)) return cache.get(userId);

    const userDoc = await firestore.collection("admins").doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : null;
    cache.set(userId, userData);
    return userData;
}

/**
 * Returns the number of whole calendar days between today and a
 * "YYYY-MM-DD" date string, computed entirely in UTC so the result never
 * depends on the Cloud Functions runtime's local timezone. This avoids the
 * classic bug where `new Date(dateString)` (UTC midnight) is compared
 * against `new Date().setHours(0,0,0,0)` (server-local midnight) — those
 * only agree if the server happens to run in UTC.
 *
 * Returns null if dateStr is missing or not a valid YYYY-MM-DD string.
 */
function daysUntil(dateStr) {
    if (!dateStr || typeof dateStr !== "string") return null;

    const match = dateStr.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!match) return null;

    const [, year, month, day] = match;
    const targetUTC = Date.UTC(Number(year), Number(month) - 1, Number(day));

    const now = new Date();
    const todayUTC = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());

    return Math.round((targetUTC - todayUTC) / (1000 * 60 * 60 * 24));
}

/**
 * Scheduled function to check stock levels daily at 8:00 AM.
 */
exports.dailyLowStockCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    logger.info("⏰ Commencing daily low stock cron check...");
    const firestore = admin.firestore();

    try {
        const medicinesSnapshot = await firestore.collection("medicines").get();
        const userMedicinesMap = {};

        medicinesSnapshot.forEach((doc) => {
            const data = doc.data();
            const totalStock = parseFloat(data.totalStock) || 0;
            const reorderLevel = parseFloat(data.reorderLevel) || 0;

            if (totalStock <= reorderLevel) {
                if (!userMedicinesMap[data.userId]) userMedicinesMap[data.userId] = [];
                userMedicinesMap[data.userId].push({ name: data.name, totalStock, unit: data.measurementUnit || data.measurement_unit || "units" });
            }
        });

        const adminCache = new Map();

        for (const userId in userMedicinesMap) {
            const userData = await getCachedAdmin(firestore, adminCache, userId);
            const prefs = userData?.notificationPreferences || {};

            if (prefs.isNotifEnabled !== false && prefs.isLowStockAlert !== false && userData?.fcmToken) {
                const meds = userMedicinesMap[userId];
                const bodyText = meds.length === 1
                    ? `${meds[0].name} is low on stock (${meds[0].totalStock} ${meds[0].unit} left).`
                    : `You have ${meds.length} items low on stock: ` + meds.map(m => m.name).join(", ");

                await safeSend(userId, {
                    notification: { title: "⚠️ Daily Low Stock Summary", body: bodyText },
                    token: userData.fcmToken,
                    data: { type: "stock_alert" }
                });
            }
        }

        logger.info(`✅ Low stock check complete. ${Object.keys(userMedicinesMap).length} user(s) had low-stock items.`);
    } catch (error) {
        logger.error("💥 Low stock check error:", error);
    }
});

/**
 * Scheduled function to check expiration dates of stocks daily at 8:00 AM.
 * Notifies once per day for any stock that is expired or within 7 days of
 * expiring, batched into a single notification per user.
 */
exports.dailyExpirationCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    logger.info("⏰ Commencing daily medicine expiration audit...");
    const firestore = admin.firestore();

    try {
        const medicinesSnapshot = await firestore.collection("medicines").get();
        const adminCache = new Map();

        // Collect all expiration alerts per user first, then send one
        // batched notification per user instead of one per stock item.
        const userAlertsMap = {};

        for (const medDoc of medicinesSnapshot.docs) {
            const medData = medDoc.data();
            const userId = medData.userId;
            if (!userId) continue;

            const stocksSnapshot = await firestore
                .collection(`medicines/${medDoc.id}/medicine_stock`)
                .get();

            for (const stockDoc of stocksSnapshot.docs) {
                const stockData = stockDoc.data();
                if (!stockData.expiryDate) continue;

                const diffDays = daysUntil(stockData.expiryDate);
                if (diffDays === null) continue;

                let message = "";
                if (diffDays <= 0) {
                    message = `${medData.name} (Stock: ${stockData.amount}) is already expired.`;
                } else if (diffDays <= 7) {
                    message = `${medData.name} (Stock: ${stockData.amount}) is about to expire in ${diffDays} day${diffDays === 1 ? "" : "s"}.`;
                }

                if (message) {
                    if (!userAlertsMap[userId]) userAlertsMap[userId] = [];
                    userAlertsMap[userId].push({
                        message,
                        medId: medDoc.id,
                        stockId: stockDoc.id,
                    });
                }
            }
        }

        for (const userId in userAlertsMap) {
            const userData = await getCachedAdmin(firestore, adminCache, userId);
            const prefs = userData?.notificationPreferences || {};

            if (prefs.isNotifEnabled !== false && prefs.isMedExpAlert !== false && userData?.fcmToken) {
                const alerts = userAlertsMap[userId];
                const body = alerts.length === 1
                    ? alerts[0].message
                    : `You have ${alerts.length} stock items needing attention: ` + alerts.map(a => a.message).join(" ");

                await safeSend(userId, {
                    notification: { title: "⚠️ Expiration Alert", body },
                    token: userData.fcmToken,
                    data: {
                        type: "med_exp_alert",
                        // For multi-item alerts, only the first item's ids are
                        // included; clients should treat `data` as a deep-link
                        // hint rather than the full alert payload.
                        medId: alerts[0].medId,
                        stockId: alerts[0].stockId,
                    }
                });
                logger.info(`📩 Sent expiration alert (${alerts.length} item(s)) to user ${userId}`);
            }
        }
    } catch (error) {
        logger.error("💥 Expiration check error:", error);
    }
});

/**
 * Scheduled function to check Intake Schedule daily at 8:00 AM.
 * Notifies 2 days before, tomorrow (1), and today (0).
 */
exports.dailyIntakeScheduleCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    logger.info("⏰ Commencing daily intake schedule check...");
    const firestore = admin.firestore();

    try {
        // nextSchedule is stored as a plain "YYYY-MM-DD" string, which sorts
        // correctly with lexicographic comparison — so a Firestore range
        // query works here and avoids reading every intake doc in the system.
        const now = new Date();
        const todayUTC = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const rangeEndUTC = new Date(todayUTC);
        rangeEndUTC.setUTCDate(rangeEndUTC.getUTCDate() + 2);

        const todayStr = todayUTC.toISOString().slice(0, 10);
        const rangeEndStr = rangeEndUTC.toISOString().slice(0, 10);

        const snapshot = await firestore.collectionGroup("medicine_intakes")
            .where("nextSchedule", ">=", todayStr)
            .where("nextSchedule", "<=", rangeEndStr)
            .get();

        const pigCache = new Map();
        const adminCache = new Map();

        for (const doc of snapshot.docs) {
            const data = doc.data();
            if (!data.nextSchedule || !data.pigId) continue;

            const diffDays = daysUntil(data.nextSchedule);
            if (diffDays === null) continue;

            // Notifies: today (0), tomorrow (1), and 2 days before (2)
            if (diffDays !== 0 && diffDays !== 1 && diffDays !== 2) continue;

            let pigData = pigCache.get(data.pigId);
            if (pigData === undefined) {
                const pigDoc = await firestore.collection("pigs").doc(data.pigId).get();
                pigData = pigDoc.exists ? pigDoc.data() : null;
                pigCache.set(data.pigId, pigData);
            }

            const userId = pigData?.userId;
            if (!userId) continue;

            // Format: 'Breed | DisplayID'
            const pigDisplayName = pigData ? `${pigData.breed} | ${pigData.displayId}` : "Unknown Pig";

            const userData = await getCachedAdmin(firestore, adminCache, userId);
            const prefs = userData?.notificationPreferences || {};

            if (prefs.isNotifEnabled === false || prefs.isVaxSchedAlert === false || !userData?.fcmToken) {
                continue;
            }

            let title = "💊 Intake Schedule Alert";
            let body = "";

            if (diffDays === 0) {
                title = "💊 Intake Schedule Today";
                body = `Time for ${data.medName} for pig ${pigDisplayName}.`;
            } else if (diffDays === 1) {
                title = "💊 Intake Schedule Tomorrow";
                body = `${data.medName} for pig ${pigDisplayName} is scheduled for tomorrow.`;
            } else {
                body = `${data.medName} for pig ${pigDisplayName} is scheduled in 2 days.`;
            }

            await safeSend(userId, {
                notification: { title, body },
                token: userData.fcmToken,
                data: { type: "vax_alert", pigId: data.pigId }
            });
        }
    } catch (error) {
        logger.error("💥 Intake check error:", error);
    }
});