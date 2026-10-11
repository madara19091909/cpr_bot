#!/usr/bin/env bash
# Generates the Flutter android/ scaffold (not committed) and applies MC Manger
# customisations: applicationId, label, Kotlin SAF bridge, documentfile dep.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_ID="com.mcmanger.android"

if [ ! -d android ]; then
  tmp=$(mktemp -d)
  cp -r lib test pubspec.yaml "$tmp"/
  flutter create --platforms=android --project-name mc_manger --org com.mcmanger.android .
  rm -rf lib test pubspec.yaml
  cp -r "$tmp"/lib "$tmp"/test "$tmp"/pubspec.yaml .
fi

GRADLE=$(ls android/app/build.gradle.kts android/app/build.gradle 2>/dev/null | head -1)
sed -i -E "s/(namespace|applicationId)( *=? *)\"[^\"]+\"/\1\2\"$APP_ID\"/" "$GRADLE"
if [[ "$GRADLE" == *.kts ]]; then
  printf '\ndependencies {\n    implementation("androidx.documentfile:documentfile:1.0.1")\n}\n' >> "$GRADLE"
else
  printf "\ndependencies {\n    implementation 'androidx.documentfile:documentfile:1.0.1'\n}\n" >> "$GRADLE"
fi

rm -rf android/app/src/main/kotlin
mkdir -p "android/app/src/main/kotlin/${APP_ID//.//}"
cp android_overlay/MainActivity.kt "android/app/src/main/kotlin/${APP_ID//.//}/MainActivity.kt"
sed -i 's/android:label="[^"]*"/android:label="MC Manger"/' android/app/src/main/AndroidManifest.xml
echo "Overlay applied: applicationId=$APP_ID"
