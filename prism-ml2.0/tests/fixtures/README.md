# Test fixtures: SYNTHETIC

Every file here is **synthetic** test data. It was written by hand to exercise validation
edge cases: impossible values, sensor-offline flags, missing fields, an NTP-failed
timestamp, a duplicate, a device-offline gap, a string-typed timestamp, and one full
schema-v2 record.

- File names start with `SYNTHETIC_`, and every record carries `"_synthetic": true`.
- IDs are prefixed `SYN-`.
- Exports built from these files get a `SYNTHETIC-` dataset version and `contains_synthetic: true`.

Never use these files for any reported metric or result.
