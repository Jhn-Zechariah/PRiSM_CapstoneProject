#!/usr/bin/env sh
# Runs the rules tests on the local Firestore emulator (demo project; never a real one).
# Copies the repo's firestore.rules next to this config because the emulator only
# loads rules from inside its config directory.
set -e
cd "$(dirname "$0")/.."
cp firestore.rules tests_firestore_rules/firestore.rules.under_test
firebase emulators:exec --config tests_firestore_rules/firebase.json --only firestore \
  --project demo-prism-rules "node tests_firestore_rules/run.mjs"
