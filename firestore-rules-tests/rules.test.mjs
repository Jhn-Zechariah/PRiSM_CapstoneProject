// Emulator tests for ../firestore.rules.   Run:  npm test   (needs Java 11+)
import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";

let env;
const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const device = () => env.authenticatedContext("esp32-pen-1", { prism_device: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-prism",
    firestore: { rules: readFileSync("../firestore.rules", "utf8"), host: "127.0.0.1", port: 8085 },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "pigs/p-alice"), { userId: "alice", name: "A" });
    await setDoc(doc(db, "pigs/p-alice/weight_history/w1"), { weightKg: 50 });
    await setDoc(doc(db, "medicines/m-alice"), { userId: "alice", name: "Vit" });
    await setDoc(doc(db, "live_sensor/latest"), { ambientHumidity: 70 });
    await setDoc(doc(db, "farms/farm-a"), { memberUids: ["alice"] });
    await setDoc(doc(db, "farms/farm-a/sensor_readings/r1"), { air_temp_c: 30 });
  });
});

// ---- unauthenticated access (what the current firmware does) is denied everywhere
test("unauthenticated clients can neither read nor write", async () => {
  await assertFails(getDoc(doc(anon(), "live_sensor/latest")));
  await assertFails(setDoc(doc(anon(), "live_sensor/latest"), { ambientHumidity: 1 }));
  await assertFails(setDoc(doc(anon(), "sprinkler_command/pending"), { state: "on" }));
  await assertFails(getDoc(doc(anon(), "pigs/p-alice")));
});

// ---- owner isolation of farm records
test("users read and edit only their own pigs", async () => {
  await assertSucceeds(getDoc(doc(alice(), "pigs/p-alice")));
  await assertFails(getDoc(doc(bob(), "pigs/p-alice")));
  await assertFails(updateDoc(doc(bob(), "pigs/p-alice"), { name: "stolen" }));
  await assertFails(deleteDoc(doc(bob(), "pigs/p-alice")));
  await assertSucceeds(getDoc(doc(alice(), "pigs/p-alice/weight_history/w1")));
  await assertFails(getDoc(doc(bob(), "pigs/p-alice/weight_history/w1")));
});

test("cannot create records for another user or change the owner", async () => {
  await assertFails(setDoc(doc(bob(), "pigs/p-new"), { userId: "alice" }));
  await assertSucceeds(setDoc(doc(bob(), "pigs/p-bob"), { userId: "bob" }));
  await assertFails(updateDoc(doc(alice(), "pigs/p-alice"), { userId: "bob" }));
  await assertFails(getDoc(doc(bob(), "medicines/m-alice")));
});

test("profiles are private", async () => {
  await assertSucceeds(setDoc(doc(alice(), "admins/alice"), { name: "Alice" }));
  await assertFails(getDoc(doc(bob(), "admins/alice")));
  await assertFails(setDoc(doc(bob(), "admins/alice"), { name: "x" }));
});

// ---- sensor data: devices write, users read
test("only devices write sensor data", async () => {
  await assertSucceeds(setDoc(doc(device(), "live_sensor/latest"), { ambientHumidity: 71 }));
  await assertSucceeds(setDoc(doc(device(), "sensor_readings_seconds/s1"), { ambientHumidity: 71 }));
  await assertFails(setDoc(doc(alice(), "live_sensor/latest"), { ambientHumidity: 0 }));
  await assertFails(setDoc(doc(alice(), "sensor_readings_seconds/fake"), { ambientHumidity: 0 }));
  await assertSucceeds(getDoc(doc(alice(), "live_sensor/latest")));
});

test("devices cannot read or modify farm records", async () => {
  await assertFails(getDoc(doc(device(), "pigs/p-alice")));
  await assertFails(setDoc(doc(device(), "pigs/p-x"), { userId: "esp32-pen-1" }));
});

test("sprinkler commands are validated", async () => {
  await assertSucceeds(setDoc(doc(alice(), "sprinkler_command/pending"), { state: "on" }));
  await assertSucceeds(setDoc(doc(device(), "sprinkler_command/pending"), { state: "off" }));
  await assertFails(setDoc(doc(alice(), "sprinkler_command/pending"), { state: "explode" }));
  await assertFails(setDoc(doc(alice(), "sprinkler_command/pending"), { state: "on", extra: 1 }));
});

// ---- multi-farm layout
test("farm sensor readings: members read, nobody writes from clients", async () => {
  await assertSucceeds(getDoc(doc(alice(), "farms/farm-a/sensor_readings/r1")));
  await assertFails(getDoc(doc(bob(), "farms/farm-a/sensor_readings/r1")));
  await assertFails(setDoc(doc(alice(), "farms/farm-a/sensor_readings/r2"), { air_temp_c: 1 }));
  await assertFails(setDoc(doc(device(), "farms/farm-a/sensor_readings/r2"), { air_temp_c: 1 }));
  await assertFails(updateDoc(doc(alice(), "farms/farm-a"), { memberUids: ["alice", "bob"] }));
});

test("unknown collections are denied", async () => {
  await assertFails(getDoc(doc(alice(), "ml_models/current")));
  await assertFails(setDoc(doc(alice(), "anything/x"), { a: 1 }));
});
