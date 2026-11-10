const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
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
function channelFor(prefs, critical = false) {
    // Critical alerts (high temp / humidity) ALWAYS play sound.
    const sound = critical || prefs.isSoundOn !== false;
    const vibrate = prefs.isVibrateOn !== false;
    const prefix = critical && sound ? "critical" : "alerts";
    return `${prefix}_${sound ? "s" : "x"}${vibrate ? "v" : "x"}`;
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

// The farm runs on Philippine time (UTC+8, no daylight saving). The app
// saves dates picked on the phone as Timestamps at local midnight, which is
// 16:00 UTC of the previous day, so calendar days must be read in UTC+8.
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** "YYYY-MM-DD" of the given instant as seen in Philippine time. */
function manilaDateStr(date) {
    return new Date(date.getTime() + MANILA_OFFSET_MS).toISOString().slice(0, 10);
}

/** The instant that Philippine-time midnight of a "YYYY-MM-DD" day begins. */
function manilaMidnight(dateStr) {
    const [year, month, day] = dateStr.split("-").map(Number);
    return new Date(Date.UTC(year, month - 1, day) - MANILA_OFFSET_MS);
}

/**
 * Returns the number of whole calendar days (Philippine time) between today
 * and a date given either as a "YYYY-MM-DD" string or a Firestore Timestamp.
 * Day counts are taken from calendar-date strings, never from raw instants,
 * so the result doesn't depend on the Cloud Functions runtime's timezone.
 *
 * Returns null if the value is missing or not a recognizable date.
 */
function daysUntil(value) {
    if (!value) return null;

    let dateStr;
    if (typeof value === "string") {
        const match = value.match(/^\d{4}-\d{2}-\d{2}/);
        if (!match) return null;
        dateStr = match[0];
    } else if (typeof value.toDate === "function") {
        dateStr = manilaDateStr(value.toDate());
    } else {
        return null;
    }

    const targetUTC = Date.parse(`${dateStr}T00:00:00Z`);
    const todayUTC = Date.parse(`${manilaDateStr(new Date())}T00:00:00Z`);

    return Math.round((targetUTC - todayUTC) / DAY_MS);
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
                    android: { notification: { channelId: channelFor(prefs) } },
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
                    android: { notification: { channelId: channelFor(prefs) } },
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
 * Clears nextSchedule on intakes whose scheduled day has already passed.
 * nextSchedule exists only to drive reminders; the intake record itself is
 * kept because it is the pig's medicine history.
 */
async function clearPassedSchedules(firestore, todayStart, todayStr) {
    const intakes = firestore.collectionGroup("medicine_intakes");
    const [timestampSnap, legacySnap] = await Promise.all([
        intakes.where("nextSchedule", "<", admin.firestore.Timestamp.fromDate(todayStart)).get(),
        // Older records stored nextSchedule as a "YYYY-MM-DD" string.
        intakes.where("nextSchedule", ">=", "").where("nextSchedule", "<", todayStr).get(),
    ]);

    const writer = firestore.bulkWriter();
    let cleared = 0;
    for (const doc of [...timestampSnap.docs, ...legacySnap.docs]) {
        writer.update(doc.ref, { nextSchedule: null });
        cleared++;
    }
    await writer.close();
    logger.info(`🧹 Cleared ${cleared} passed intake schedule(s).`);
}

/**
 * Scheduled function to check Intake Schedule daily at 8:00 AM.
 * Notifies 2 days before, tomorrow (1), and today (0), then clears
 * schedules whose day has already passed.
 */
exports.dailyIntakeScheduleCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    logger.info("⏰ Commencing daily intake schedule check...");
    const firestore = admin.firestore();

    // Today .. today+2 in Philippine time, as both Timestamp bounds (current
    // records) and "YYYY-MM-DD" bounds (older records saved as strings).
    const todayStr = manilaDateStr(new Date());
    const todayStart = manilaMidnight(todayStr);
    const rangeEnd = new Date(todayStart.getTime() + 3 * DAY_MS); // exclusive
    const rangeEndStr = manilaDateStr(new Date(rangeEnd.getTime() - DAY_MS));

    try {
        const intakes = firestore.collectionGroup("medicine_intakes");
        const [timestampSnap, legacySnap] = await Promise.all([
            intakes
                .where("nextSchedule", ">=", admin.firestore.Timestamp.fromDate(todayStart))
                .where("nextSchedule", "<", admin.firestore.Timestamp.fromDate(rangeEnd))
                .get(),
            intakes
                .where("nextSchedule", ">=", todayStr)
                .where("nextSchedule", "<=", rangeEndStr)
                .get(),
        ]);

        const pigCache = new Map();
        const adminCache = new Map();

        for (const doc of [...timestampSnap.docs, ...legacySnap.docs]) {
            const data = doc.data();
            if (!data.nextSchedule || !data.pigId) continue;
            if (data.status === "Discontinued") continue;

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
                android: { notification: { channelId: channelFor(prefs) } },
                token: userData.fcmToken,
                data: { type: "vax_alert", pigId: data.pigId }
            });
        }
    } catch (error) {
        logger.error("💥 Intake check error:", error);
    }

    // Separate try so a failed reminder run never blocks the cleanup.
    try {
        await clearPassedSchedules(firestore, todayStart, todayStr);
    } catch (error) {
        logger.error("💥 Passed schedule cleanup error:", error);
    }
});

/**
 * Real-time trigger on live_sensor/latest. Fires whenever the ESP32 pushes
 * a new live reading. Compares pigBodyTemp/ambientHumidity against each admin's saved
 * IoT thresholds (admins/{uid}.iotThresholds) and sends a push if a metric
 * is at or above its configured max.
 *
 * Debounce: each admin doc tracks `iotAlertState.{tempAvg|humidity}` as a
 * boolean "currently over threshold" flag. A notification is only sent on
 * the transition from false -> true, so the user gets one alert when the
 * limit is first breached instead of one every time live_sensor updates
 * (which can be as often as every few seconds). The flag resets to false
 * once the reading drops back under the threshold, re-arming the alert
 * for the next breach.
 */
const IOT_ADMINS_CACHE_MS = 60 * 1000;
let iotAdminsCache = null; // { fetchedAt, admins: [{ id, ref, data }] }

/**
 * Admins with IoT alerts on, cached per function instance for one minute.
 * The app always writes isIotEnabled together with the thresholds.
 */
async function getIotAdmins(firestore) {
    const now = Date.now();
    if (iotAdminsCache && now - iotAdminsCache.fetchedAt < IOT_ADMINS_CACHE_MS) {
        return iotAdminsCache.admins;
    }
    const snapshot = await firestore
        .collection("admins")
        .where("iotThresholds.isIotEnabled", "==", true)
        .get();
    iotAdminsCache = {
        fetchedAt: now,
        admins: snapshot.docs.map((d) => ({ id: d.id, ref: d.ref, data: d.data() })),
    };
    return iotAdminsCache.admins;
}

/**
 * Compares one live reading with an admin's thresholds. Returns null when
 * the admin should not be alerted at all, otherwise the alert-state
 * updates to write and the breach messages to send.
 */
function checkIotThresholds(userData, tempAvg, humidity, hasTemp, hasHumidity) {
    const thresholds = userData.iotThresholds;
    if (!thresholds || thresholds.isIotEnabled === false) return null;

    const prefs = userData.notificationPreferences || {};
    if (prefs.isNotifEnabled === false) return null;
    if (!userData.fcmToken) return null;

    const alertState = userData.iotAlertState || {};
    const updates = {};
    const breaches = [];

    // --- Temperature check ---
    if (
        hasTemp &&
        typeof thresholds.maxTemp === "number" &&
        prefs.isHighTempAlert !== false
    ) {
        const isOver = tempAvg >= thresholds.maxTemp;
        const wasOver = alertState.tempAvg === true;

        if (isOver && !wasOver) {
            breaches.push(
                `Body temperature is ${tempAvg.toFixed(1)}°C, at or above the ${thresholds.maxTemp}°C limit.`
            );
        }
        if (isOver !== wasOver) {
            updates["iotAlertState.tempAvg"] = isOver;
        }
    }

    // --- Humidity check ---
    if (
        hasHumidity &&
        typeof thresholds.maxHumidity === "number" &&
        prefs.isHighHumidityAlert !== false
    ) {
        const isOver = humidity >= thresholds.maxHumidity;
        const wasOver = alertState.humidity === true;

        if (isOver && !wasOver) {
            breaches.push(
                `Humidity is ${humidity.toFixed(1)}%, at or above the ${thresholds.maxHumidity}% limit.`
            );
        }
        if (isOver !== wasOver) {
            updates["iotAlertState.humidity"] = isOver;
        }
    }

    return { userData, prefs, updates, breaches };
}

exports.onLiveSensorUpdate = onDocumentWritten(
    "live_sensor/latest",
    async (event) => {
        const after = event.data?.after?.data();
        if (!after) return; // doc deleted, nothing to check

        // Field names as written by the ESP32 firmware. A reading flagged
        // invalid (sensor read failed) is treated as missing.
        const tempAvg = after.pigBodyTempValid === false ? NaN : parseFloat(after.pigBodyTemp);
        const humidity = after.ambientHumidityValid === false ? NaN : parseFloat(after.ambientHumidity);

        const hasTemp = !Number.isNaN(tempAvg);
        const hasHumidity = !Number.isNaN(humidity);
        if (!hasTemp && !hasHumidity) return;

        // This runs on every ESP32 push (~8,640/day). Reading the admins on
        // every push used most of the daily Firestore read quota, so the list
        // is cached per function instance and refreshed at most once a minute.
        const firestore = admin.firestore();
        const cachedAdmins = await getIotAdmins(firestore);

        for (const cached of cachedAdmins) {
            const userId = cached.id;
            let result = checkIotThresholds(cached.data, tempAvg, humidity, hasTemp, hasHumidity);
            if (!result) continue;

            // Only when an alert state is about to change: re-read this admin
            // fresh, so a stale cache can never send a duplicate alert or
            // use thresholds that were just changed in the app.
            if (Object.keys(result.updates).length > 0) {
                const fresh = await cached.ref.get();
                if (!fresh.exists) continue;
                cached.data = fresh.data();
                result = checkIotThresholds(cached.data, tempAvg, humidity, hasTemp, hasHumidity);
                if (!result) continue;
            }

            const { userData, prefs, updates, breaches } = result;

            // Persist the new debounce state regardless of whether we send,
            // so "over" / "under" transitions stay accurate going forward.
            if (Object.keys(updates).length > 0) {
                await cached.ref.update(updates);
                // Keep the cached copy in step with what was just written.
                const state = { ...(cached.data.iotAlertState || {}) };
                if ("iotAlertState.tempAvg" in updates) state.tempAvg = updates["iotAlertState.tempAvg"];
                if ("iotAlertState.humidity" in updates) state.humidity = updates["iotAlertState.humidity"];
                cached.data = { ...cached.data, iotAlertState: state };
            }

            if (breaches.length === 0) continue;

            const body = breaches.length === 1
                ? breaches[0]
                : breaches.join(" ");

            await safeSend(userId, {
                notification: { title: "🌡️ IoT Threshold Alert", body },
                android: { notification: { channelId: channelFor(prefs, true) } },
                token: userData.fcmToken,
                data: { type: "iot_threshold_alert" },
            });

            logger.info(
                `📩 Sent IoT threshold alert to user ${userId}: ${body}`
            );
        }
    }
);