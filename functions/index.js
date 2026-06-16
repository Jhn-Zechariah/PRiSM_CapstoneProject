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
 * Scheduled function to check expiration dates of stocks daily at 8:00 AM.
 */
exports.dailyExpirationCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    console.log("⏰ Commencing daily medicine expiration audit...");
    const firestore = admin.firestore();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    try {
        const medicinesSnapshot = await firestore.collection("medicines").get();

        for (const medDoc of medicinesSnapshot.docs) {
            const medData = medDoc.data();
            const userId = medData.userId;

            const stocksSnapshot = await firestore.collection(`medicines/${medDoc.id}/medicine_stock`).get();

            for (const stockDoc of stocksSnapshot.docs) {
                const stockData = stockDoc.data();
                if (!stockData.expiryDate) continue;

                const expiryDate = new Date(stockData.expiryDate);
                expiryDate.setHours(0, 0, 0, 0);
                const diffDays = Math.ceil((expiryDate - today) / (1000 * 60 * 60 * 24));

                let message = "";
                if (diffDays <= 0) {
                    message = `${medData.name} (Stock: ${stockData.amount}) is already expired.`;
                } else if (diffDays <= 7) {
                    message = `${medData.name} (Stock: ${stockData.amount}) is about to expire in ${diffDays} day${diffDays === 1 ? "" : "s"}.`;
                }

                if (message) {
                    const userDoc = await firestore.collection("admins").doc(userId).get();
                    const userData = userDoc.data();
                    const prefs = userData?.notificationPreferences || {};

                    if (prefs.isNotifEnabled !== false && prefs.isMedExpAlert !== false && userData?.fcmToken) {
                        await admin.messaging().send({
                            notification: { title: "⚠️ Expiration Alert", body: message },
                            token: userData.fcmToken,
                            data: { type: "med_exp_alert", medId: medDoc.id, stockId: stockDoc.id }
                        });
                        console.log(`📩 Sent expiration alert for ${medData.name} to user ${userId}`);
                    }
                }
            }
        }
    } catch (error) { console.error("💥 Expiration check error:", error); }
});

/**
 * Scheduled function to check Intake Schedule daily at 8:00 AM.
 * Notifies 2 days before, tomorrow (1), and today (0).
 */
exports.dailyIntakeScheduleCheck = onSchedule({
    schedule: "0 8 * * *",
    timeZone: "Asia/Manila",
}, async (event) => {
    console.log("⏰ Commencing daily intake schedule check...");
    const firestore = admin.firestore();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    try {
        const snapshot = await firestore.collectionGroup("medicine_intakes").get();

        for (const doc of snapshot.docs) {
            const data = doc.data();
            if (!data.nextSchedule) continue;

            const scheduleDate = new Date(data.nextSchedule);
            scheduleDate.setHours(0, 0, 0, 0);
            const diffDays = Math.ceil((scheduleDate - today) / (1000 * 60 * 60 * 24));

            // Notifies: today (0), tomorrow (1), and 2 days before (2)
            if (diffDays === 0 || diffDays === 1 || diffDays === 2) {
                const pigDoc = await firestore.collection("pigs").doc(data.pigId).get();
                const pigData = pigDoc.data();
                const userId = pigData?.userId;
                if (!userId) continue;

                // Format: 'Breed | DisplayID'
                const pigDisplayName = pigData ? `${pigData.breed} | ${pigData.displayId}` : "Unknown Pig";

                const userDoc = await firestore.collection("admins").doc(userId).get();
                const userData = userDoc.data();
                const prefs = userData?.notificationPreferences || {};

                if (prefs.isNotifEnabled !== false && prefs.isVaxSchedAlert !== false && userData?.fcmToken) {
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

                    await admin.messaging().send({
                        notification: { title, body },
                        token: userData.fcmToken,
                        data: { type: "vax_alert", pigId: data.pigId }
                    });
                }
            }
        }
    } catch (error) { console.error("💥 Intake check error:", error); }
});
