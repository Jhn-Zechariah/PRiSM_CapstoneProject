# Proposal: ESP32 sensor record schema v2 (AWAITING APPROVAL)

**Status:** proposal only. **No firmware has been edited.** The firmware source is not in this
repository on any branch (see `REPO_AUDIT.md` §7), so every statement below about current
firmware behavior is inferred from the Flutter code and is **unverified**.

## 1. What the firmware is known to send today (inferred)

| Target | Fields the app reads | Evidence |
|---|---|---|
| `live_sensor/latest` (overwritten every ~10 s) | `timestamp`, `pigBodyTemp`/`Valid`, `ambientTemp`/`Valid`, `ambientHumidity`/`Valid`, **`thermalPixels` (raw 64-pixel frame)**, `waterPct`, `waterStatus`, `sprinkler`, `tempStatus`, `pigStatus`, `ip`, … | `Dashboard_Screen.dart:1000-1108` |
| `sensor_readings_seconds/{id}` (history) | `timestamp` (Timestamp), `pigBodyTemp`, `pigBodyTempValid`, `ambientHumidity`, `ambientHumidityValid` | `temperaturemonitoring.dart:693-724`, `humiditymonitoring.dart:775,970,1166` |
| `sensor_readings_hourly/{id}` | `timestamp`, `min`, `max`, `sum`, `count` | `temperaturemonitoring.dart:1148-1264` |

Conclusions:
- **The raw AMG8833 frame reaches only the live document and is overwritten.** History keeps only the summary `pigBodyTemp`. The app comment says so: "no thermal history is stored" (`Dashboard_Screen.dart:1100-1102`).
- How `pigBodyTemp` is computed (max? mean?) is unknown.
- **Offline buffering:** there is no evidence that it exists. I am **not** claiming it does. Unknown until the firmware source is available.
- **Document IDs** for history records are unknown. If the firmware uses auto-IDs (`add()` / POST without an ID), a retried write creates a duplicate.

## 2. Proposed change: additive only

Applies to the write to `sensor_readings_seconds`. `live_sensor/latest`, `sensor_readings_hourly`, `sprinkler_*` and all control logic stay **unchanged**.

**Keep exactly as they are** (the monitoring screens depend on them):
- `timestamp` as a **Firestore Timestamp**
- `pigBodyTemp`
- `pigBodyTempValid`
- `ambientHumidity`
- `ambientHumidityValid`

**Add these fields:**

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | int `2` | lets the pipeline tell v1 from v2 |
| `source` | `"sensor"` | separates sensor rows from manual corrections |
| `deviceId` | string, e.g. MAC-derived `"esp32-a1b2c3"` | which board |
| `penId` | string, configured per board | which pen the board watches |
| `ntpSynced` | bool | `false` if the time came from a failed NTP sync |
| `buffered` | bool | `true` if replayed from the offline buffer (§4) |
| `wifiRssi` | int, dBm | connectivity quality |
| `uptimeSec` | int | detects reboots |
| `ambientTemp`, `ambientTempValid` | number, bool | DHT22 air temperature (already in the live doc) |
| `thermalPixels` | array of 64 numbers, °C, row-major, rounded to 0.25 (the sensor's resolution) | **raw frame** (already in the live doc) |
| `amgThermistor` | number, °C | AMG8833 on-board thermistor (`readThermistor()` in the Adafruit library) |
| `waterPct`, `waterStatus` | as in the live doc | HC-SR04 level |
| `waterDistanceCm` | number | raw HC-SR04 distance, before conversion to % |
| `sprinkler` | bool | relay state at sample time |
| `sprinklerActiveSec` | int | seconds ON in the current activation, `0` when OFF |

**Deterministic document ID:** `"{deviceId}-{epochSecondsUTC}"`.
- Write with a **create** call that fails if the document exists. With the Firebase ESP Client library, that is `Firestore.createDocument` with an explicit document ID.
- A retry then never duplicates, and an existing record is never overwritten (immutability).
- `ALREADY_EXISTS` must be treated as success.

**Example v2 history document:**
```json
{ "timestamp": <Timestamp 2026-10-19T00:15:20Z>, "schemaVersion": 2, "source": "sensor",
  "deviceId": "esp32-a1b2c3", "penId": "pen-1", "ntpSynced": true, "buffered": false,
  "wifiRssi": -61, "uptimeSec": 905,
  "ambientTemp": 29.4, "ambientTempValid": true, "ambientHumidity": 79.1, "ambientHumidityValid": true,
  "pigBodyTemp": 31.75, "pigBodyTempValid": true, "thermalPixels": [64 numbers], "amgThermistor": 30.25,
  "waterPct": 64.0, "waterDistanceCm": 41.2, "waterStatus": "Normal",
  "sprinkler": false, "sprinklerActiveSec": 0 }
```

### Cost decision needed

A frame adds roughly 0.5–1 KB per document. At the current ~10 s cadence (unverified) that is about 8,640 docs/day, or roughly 5–9 MB/day: about 0.15–0.26 GB/month against the Spark plan's 1 GiB. Options:
- **(a)** Frame in every history record.
- **(b)** Frame every 6th record (once a minute). All other fields stay every record.
- **(c)** Frame only when the pipeline's thermal-anomaly step needs it (later phase).

Recommendation: **(b)**.

## 3. Immutability on the server (proposal, not deployed)

The repo has no `firestore.rules` file. Once you confirm how the ESP32 authenticates (Firebase Auth device user? API key with open rules?), the rules should allow:
```
match /sensor_readings_seconds/{id} { allow create: if <device is authenticated>; allow update, delete: if false; allow read: if request.auth != null; }
match /sensor_corrections/{id}      { allow create: if request.auth != null;      allow update, delete: if false; allow read: if request.auth != null; }
```
I will not write or deploy rules until the device auth method is known. Wrong rules would stop logging.

## 4. Offline buffering: minimal safe design (not implemented)

1. On each sample, build the v2 record **with the device timestamp at read time** and try the create call with a short timeout (≤ 3 s).
2. On failure, append the JSON line to a **bounded** LittleFS file such as `/buf.jsonl` (e.g. 1 MB cap: ≈ 1,000 records with frames, ≈ 5,000 without) and mark it `buffered: true`.
3. While online, drain the **oldest** lines first, a few per loop iteration, using the same deterministic ID. Remove a line only after success or `ALREADY_EXISTS`.
4. When the buffer is full, drop the oldest line and count the drops. Send the count as `bufferDropped` on the next record.
5. If NTP is not synced, record `millis()` at read time. Once NTP syncs, compute `timestamp = syncUtc - (millisAtSync - millisAtRead)` before sending. If the board reboots before syncing, send with `ntpSynced: false` and let validation flag it.
6. **Safety:** buffering and draining must never block or delay the sprinkler, schedule or manual ON/OFF logic. They run only in the logging path, with short timeouts. Only history records are buffered, never `live_sensor/latest` or commands.

## 5. What does not change

- Monitoring screens: same collections, same field names, same `timestamp` type.
- Thresholds, schedules (`sprinkler_settings/config`), manual ON/OFF (`sprinkler_command/pending`, LAN `/sprinkler`) and ESP32 safety logic.
- ML: not involved. Logging is ESP32 → Firestore only, so it continues when the ML API is down.

## 6. To proceed I need

1. The firmware source (so I can see the current history write, its cadence and ID scheme).
2. Your approval of §2, including the cost option (a), (b) or (c).
3. Whether to implement §4 buffering.
4. The ESP32's Firestore authentication method (for §3).
