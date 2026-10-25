// Firestore rules tests against the LOCAL emulator only (project id demo-prism-rules,
// never a real project). No dependencies: Node's fetch + the emulator REST API.
// All users, tokens and documents here are SYNTHETIC.
//
//   sh tests_firestore_rules/test.sh

const P = 'demo-prism-rules';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8089';
const BASE = `http://${HOST}/v1/projects/${P}/databases/(default)/documents`;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
// Unsigned test token, accepted only by the emulator.
function token(uid, claims = {}) {
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${P}`, aud: P, iat: now, exp: now + 3600, auth_time: now,
    sub: uid, user_id: uid, firebase: { sign_in_provider: 'custom', identities: {} }, ...claims,
  })}.`;
}
const T = {
  a: token('SYN-userA'), b: token('SYN-userB'),
  admin: token('SYN-admin', { role: 'admin' }), device: token('SYN-esp32', { device: true }),
  owner: 'owner', none: null,
};

function enc(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: fields(v) } };
}
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, enc(v)]));

async function call(method, url, tok, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (tok) headers.Authorization = `Bearer ${tok}`;
  const r = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  return r.status;
}
const set = (path, data, tok) => call('PATCH', `${BASE}/${path}`, tok, { fields: fields(data) });
const merge = (path, data, tok) => call('PATCH',
  `${BASE}/${path}?${Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join('&')}`, tok, { fields: fields(data) });
const get = (path, tok) => call('GET', `${BASE}/${path}`, tok);
const del = (path, tok) => call('DELETE', `${BASE}/${path}`, tok);
const commit = (writes, tok) => call('POST', `${BASE}:commit`, tok, {
  writes: writes.map(([path, data]) => ({
    update: { name: `projects/${P}/databases/(default)/documents/${path}`, fields: fields(data) } })),
});
const groupQuery = (collectionId, where, tok) => call('POST', `${BASE}:runQuery`, tok, {
  structuredQuery: {
    from: [{ collectionId, allDescendants: true }],
    ...(where ? { where: { fieldFilter: { field: { fieldPath: where[0] }, op: 'EQUAL', value: enc(where[1]) } } } : {}),
  },
});

let failed = 0;
async function expect(name, promise, allowed) {
  const status = await promise;
  const ok = allowed ? (status === 200 || status === 404) : status === 403;
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${allowed ? 'allow' : 'deny '}  ${name}  (HTTP ${status})`);
}

// ---- seed with the emulator's rules-bypassing owner token
await call('DELETE', `http://${HOST}/emulator/v1/projects/${P}/databases/(default)/documents`, null);
await set('pigs/SYN-pigA', { userId: 'SYN-userA', breed: 'SYN' }, T.owner);
await set('pigs/SYN-pigA/medicine_intakes/SYN-i1', { userId: 'SYN-userA', category: 'Vaccine' }, T.owner);
await set('pigs/SYN-pigB', { userId: 'SYN-userB', breed: 'SYN' }, T.owner);
await set('pigs/SYN-pigB/medicine_intakes/SYN-i2', { userId: 'SYN-userB', category: 'Vaccine' }, T.owner);
await set('sensor_readings_seconds/SYN-r1', { pigBodyTemp: 31.5, ambientHumidity: 78 }, T.owner);
await set('sprinkler_settings/config', { isIotEnabled: true, deviceOnlyField: 1 }, T.owner);
await set('assessment_results/SYN-res1', { userId: 'SYN-userA', origin: 'api' }, T.owner);
await set('admins/SYN-userB', { username: 'SYN-b' }, T.owner);

const result = {
  userId: 'SYN-userA', origin: 'api', component: 'thi_band', method: 'rule', modelVersion: null,
  inputSummary: [{ name: 'dht_temp_c', value: 30, source: 'sensor' }], assessedAt: '2026-10-19T06:00:00Z',
  rawRef: { path: 'live_sensor/latest', docId: null },
};

// ---- manual farm records
await expect('owner reads own pig', get('pigs/SYN-pigA', T.a), true);
await expect('other user reads pig', get('pigs/SYN-pigA', T.b), false);
await expect('create pig for someone else', set('pigs/SYN-pigX', { userId: 'SYN-userB' }, T.a), false);
await expect('addPig transaction: pig + weight_history in one commit (getAfter)',
  commit([['pigs/SYN-pigNew', { userId: 'SYN-userA', breed: 'SYN' }],
          ['pigs/SYN-pigNew/weight_history/SYN-w1', { weightKg: 10, notes: 'Initial weight' }]], T.a), true);
await expect('write other user\'s weight_history', set('pigs/SYN-pigB/weight_history/SYN-w9', { weightKg: 1 }, T.a), false);
await expect('collection-group intakes filtered by own userId', groupQuery('medicine_intakes', ['userId', 'SYN-userA'], T.a), true);
await expect('collection-group intakes filtered by category only (old dashboard query)',
  groupQuery('medicine_intakes', ['category', 'Vaccine'], T.a), false);
await expect('read own user doc', get('admins/SYN-userA', T.a), true);
await expect('read another user doc', get('admins/SYN-userB', T.a), false);

// ---- raw sensor observations
await expect('signed-in user reads sensor history', get('sensor_readings_seconds/SYN-r1', T.a), true);
await expect('unauthenticated read of sensor history', get('sensor_readings_seconds/SYN-r1', T.none), false);
await expect('user writes a raw observation', set('sensor_readings_seconds/SYN-r2', { pigBodyTemp: 1 }, T.a), false);
await expect('device creates a raw observation', set('sensor_readings_seconds/SYN-r3', { pigBodyTemp: 31 }, T.device), true);
await expect('device overwrites a raw observation', set('sensor_readings_seconds/SYN-r1', { pigBodyTemp: 99 }, T.device), false);
await expect('device deletes a raw observation', del('sensor_readings_seconds/SYN-r1', T.device), false);

// ---- sprinkler control (same payloads the app sends today)
await expect('app sprinkler command {state:on}', set('sprinkler_command/pending', { state: 'on' }, T.a), true);
await expect('sprinkler command with an invalid state', set('sprinkler_command/pending', { state: 'boom' }, T.a), false);
await expect('sprinkler command with extra fields', set('sprinkler_command/pending', { state: 'on', x: 1 }, T.a), false);
await expect('device writes sprinkler command', set('sprinkler_command/pending', { state: 'off' }, T.device), true);
await expect('IoT settings merge-save (4 app keys) keeps device field',
  merge('sprinkler_settings/config', { isIotEnabled: false, isSprinklerAuto: true, schedule: '6:00 PM', durationMins: 5 }, T.a), true);
await expect('IoT settings write of another key', merge('sprinkler_settings/config', { maxTemp: 99 }, T.a), false);
await expect('unauthenticated sprinkler command', set('sprinkler_command/pending', { state: 'on' }, T.none), false);

// ---- derived results
await expect('store own assessment result', set('assessment_results/SYN-res2', result, T.a), true);
await expect('store result for another user', set('assessment_results/SYN-res3', { ...result, userId: 'SYN-userB' }, T.a), false);
await expect('store phone-computed result', set('assessment_results/SYN-res4', { ...result, origin: 'phone' }, T.a), false);
await expect('overwrite existing result', set('assessment_results/SYN-res1', result, T.a), false);
await expect('other user reads result', get('assessment_results/SYN-res1', T.b), false);
await expect('user creates a correction', set('sensor_corrections/SYN-c1', { recordId: 'SYN-r1' }, T.a), false);
await expect('admin creates a correction', set('sensor_corrections/SYN-c2', { recordId: 'SYN-r1' }, T.admin), true);
await expect('write to an unlisted collection', set('anything/SYN-x', { a: 1 }, T.a), false);

console.log(failed ? `\n${failed} rule check(s) FAILED` : '\nall rule checks passed');
process.exit(failed ? 1 : 0);
