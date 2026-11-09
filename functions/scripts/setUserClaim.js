/**
 * Sets or removes a PRISM custom claim on a Firebase Auth user.
 * firestore.rules and the Cloud Functions check these claims:
 *
 *   device  The ESP32 account. Allowed to upload sensor data, sprinkler logs
 *           and live_sensor (isDevice() in firestore.rules).
 *   farm    The farm owner account. The ONLY user account allowed to see
 *           sensor data, control the sprinkler and receive IoT alerts
 *           (isFarmUser() in firestore.rules).
 *
 * The Firebase Console cannot set custom claims, so this uses the Admin SDK.
 *
 * Usage (from the functions/ folder, after `gcloud auth application-default login`
 * with an account that has Firebase Admin / Owner on the project):
 *   node scripts/setUserClaim.js <email> device            -> set device claim
 *   node scripts/setUserClaim.js <email> farm              -> set farm claim
 *   node scripts/setUserClaim.js <email> farm --remove     -> remove it
 *   node scripts/setUserClaim.js --list                    -> list users holding a claim
 *
 * A claim reaches the user's ID token only after the token is refreshed:
 * sign out and back in on the app (or wait up to 1 hour). The ESP32 refreshes
 * automatically within 5 minutes of a 403, or reboot it.
 */
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

const PROJECT_ID = "prism-3cd2c";
const CLAIMS = ["device", "farm"];

initializeApp({ projectId: PROJECT_ID });

async function listClaimHolders() {
    let pageToken;
    let found = 0;
    do {
        const page = await getAuth().listUsers(1000, pageToken);
        for (const u of page.users) {
            const held = CLAIMS.filter((c) => u.customClaims && u.customClaims[c] === true);
            if (held.length) {
                found++;
                console.log(`${u.email || "(no email)"}  uid=${u.uid}  claims=${held.join(",")}`);
            }
        }
        pageToken = page.pageToken;
    } while (pageToken);
    if (!found) console.log("No users hold a PRISM claim.");
}

async function main() {
    if (process.argv.includes("--list")) return listClaimHolders();

    const [email, claim] = process.argv.slice(2);
    const remove = process.argv.includes("--remove");
    if (!email || !CLAIMS.includes(claim)) {
        console.error("Usage: node scripts/setUserClaim.js <email> <device|farm> [--remove]");
        console.error("       node scripts/setUserClaim.js --list");
        process.exit(1);
    }

    const user = await getAuth().getUserByEmail(email);
    const claims = { ...(user.customClaims || {}) };
    if (remove) delete claims[claim];
    else claims[claim] = true;

    await getAuth().setCustomUserClaims(user.uid, claims);
    console.log(`${remove ? "Removed" : "Set"} '${claim}' claim on ${email} (uid ${user.uid}) in ${PROJECT_ID}.`);
    console.log("Current claims:", JSON.stringify(claims));
    if (!remove) console.log("The user must sign out and back in (or wait up to 1 hour) for it to apply.");
}

main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
});
