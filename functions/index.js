const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();

/**
 * Scheduled function to check stock levels daily at 8:00 AM.
 */
exports.dailyLowStockCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    console.log("⏰ Commencing daily low stock cron check...");
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
                userMedicinesMap[data.userId].push({ name: data.name, totalStock, unit: data.measurement_unit || "units" });
            }
        });

        for (const userId in userMedicinesMap) {
            const userDoc = await firestore.collection("admins").doc(userId).get();
            const userData = userDoc.data();
            const prefs = userData?.notificationPreferences || {};

            if (prefs.isNotifEnabled !== false && prefs.isLowStockAlert !== false && userData?.fcmToken) {
                const meds = userMedicinesMap[userId];
                const bodyText = meds.length === 1
                    ? `${meds[0].name} is low on stock (${meds[0].totalStock} ${meds[0].unit} left).`
                    : `You have ${meds.length} items low on stock: ` + meds.map(m => m.name).join(", ");

                await admin.messaging().send({
                    notification: { title: "⚠️ Daily Low Stock Summary", body: bodyText },
                    token: userData.fcmToken,
                    data: { type: "stock_alert" }
                });
            }
        }
    } catch (error) { console.error(error); }
});

/**
 * Scheduled function to check expiration dates daily at 8:00 AM.
 */
exports.dailyExpirationCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    console.log("⏰ Commencing daily expiration audit...");
    const firestore = admin.firestore();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    try {
        const snapshot = await firestore.collection("medicines").get();

        for (const doc of snapshot.docs) {
            const data = doc.data();
            if (!data.expiryDate || !data.userId) continue;

            const expiryDate = new Date(data.expiryDate);
            expiryDate.setHours(0, 0, 0, 0);
            const diffDays = Math.ceil((expiryDate - today) / (1000 * 60 * 60 * 24));

            let message = "";
            if (diffDays < 0) {
                message = `${data.name} is already expired.`;
            } else if (diffDays <= 7) {
                message = `${data.name} is about to expire in ${diffDays} day${diffDays === 1 ? "" : "s"}.`;
            }

            if (message) {
                const userDoc = await firestore.collection("admins").doc(data.userId).get();
                const userData = userDoc.data();
                const prefs = userData?.notificationPreferences || {};

                if (prefs.isNotifEnabled !== false && prefs.isMedExpAlert !== false && userData?.fcmToken) {
                    await admin.messaging().send({
                        notification: { title: "⚠️ Expiration Alert", body: message },
                        token: userData.fcmToken,
                        data: { type: "med_exp_alert" }
                    });
                }
            }
        }
    } catch (error) { console.error(error); }
});
