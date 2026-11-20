#!/usr/bin/env bash
# One-time local setup for Ruby Invoice.
# Requires the Flutter SDK: https://docs.flutter.dev/get-started/install
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/4] Generating Android platform folder (keeps lib/ and pubspec.yaml)..."
flutter create . --platforms android --project-name ruby_invoice --org com.rubyinvoice

echo "[2/4] Applying Ruby Invoice Android config (label, permissions, minSdk)..."
bash tool/apply_android_config.sh

echo "[3/4] Installing dependencies..."
flutter pub get

echo "[4/4] Generating launcher icons from assets/icon/app_icon.png..."
dart run flutter_launcher_icons

echo ""
echo "Setup complete."
echo "  Run the app:   flutter run"
echo "  Firebase sync: follow docs/FIREBASE_SETUP.md"
