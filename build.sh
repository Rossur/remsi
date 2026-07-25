#!/bin/bash
set -e

# Configure Git to trust all directories in this builder container
git config --global --add safe.directory '*'

FLUTTER_VERSION="3.22.2"
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_TAR}"

echo "=== [BUILD] Downloading Flutter SDK v${FLUTTER_VERSION} ==="
curl -L -o "$FLUTTER_TAR" "$FLUTTER_URL"

echo "=== [BUILD] Extracting Flutter SDK ==="
tar xf "$FLUTTER_TAR"
rm "$FLUTTER_TAR"

export PATH="$PATH:$(pwd)/flutter/bin"

echo "=== [BUILD] Flutter doctor & configuration ==="
flutter doctor
flutter config --enable-web

echo "=== [BUILD] Building Flutter Web App ==="
cd remsi_app
flutter pub get
flutter build web --release --base-href "/app/"

echo "=== [BUILD] Preparing Deployment Folder ==="
cd ..
mkdir -p dist

# 1. Copy the original premium HTML/JS dashboard & its icons to the root of dist
cp index.html dist/
if [ -d "icons" ]; then
  cp -r icons dist/
fi

# 2. Copy the compiled Flutter Web PWA to the /app/ subfolder
mkdir -p dist/app
cp -r remsi_app/build/web/* dist/app/
cp remsi_app/web/firebase-messaging-sw.js dist/

echo "=== [BUILD] Success! ==="
