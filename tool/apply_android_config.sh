#!/usr/bin/env bash
# Applies Ruby Invoice's Android customizations to a freshly generated
# android/ folder (run by tool/bootstrap.sh and by CI when needed).
set -euo pipefail
cd "$(dirname "$0")/.."

MAIN="android/app/src/main/AndroidManifest.xml"

echo "- Setting app label to 'Ruby Invoice'..."
sed -i.bak 's/android:label="[^"]*"/android:label="Ruby Invoice"/' "$MAIN"

echo "- Adding INTERNET / NETWORK permissions (sync + update check)..."
if ! grep -q 'android.permission.INTERNET' "$MAIN"; then
  sed -i.bak 's#<application#    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />\n    <application#' "$MAIN"
fi

echo "- Adding REQUEST_INSTALL_PACKAGES (in-app update APK install)..."
if ! grep -q 'REQUEST_INSTALL_PACKAGES' "$MAIN"; then
  sed -i.bak 's#<application#    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <application#' "$MAIN"
fi

echo "- Raising minSdk to 24 (plugin requirement)..."
if [ -f android/app/build.gradle.kts ]; then
  sed -i.bak 's/minSdk = .*/minSdk = 24/' android/app/build.gradle.kts
elif [ -f android/app/build.gradle ]; then
  sed -i.bak 's/minSdkVersion .*/minSdkVersion 24/' android/app/build.gradle
fi

# Clean sed backup files
rm -f "$MAIN.bak" android/app/build.gradle.kts.bak android/app/build.gradle.bak

echo "Android config applied."
