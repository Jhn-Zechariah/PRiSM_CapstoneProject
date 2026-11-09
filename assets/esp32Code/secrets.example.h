// PRISM ESP32 secrets: TEMPLATE.
//
// Copy this file to "secrets.h" in the same sketch folder as the main code
// and fill in the real values. secrets.h is in .gitignore: never commit it.
#pragma once

// Home WiFi
#define WIFI_SSID     "your-wifi-name"
#define WIFI_PASSWORD "your-wifi-password"

// Firebase project (Project settings > General). The web API key is not a
// secret by itself; the Firestore rules are what protect the data.
#define FIREBASE_PROJECT_ID_VALUE "prism-3cd2c"
#define FIREBASE_API_KEY_VALUE    "your-firebase-web-api-key"

// Device account the ESP32 signs in with (Firebase console > Authentication >
// Users > Add user). Use a long random password and do not use this account
// in the app. Its UID goes into firestore.rules (isDevice()).
#define DEVICE_EMAIL    "esp32@prism.local"
#define DEVICE_PASSWORD "a-long-random-password"

// Shared key for the ESP32's local web server (POST /sprinkler).
// The app must be built with the same value:
//   flutter run --dart-define=PRISM_LAN_KEY=<same value>
// Use at least 16 random characters.
#define LAN_KEY "change-me-to-a-random-string"
