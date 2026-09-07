#!/usr/bin/env bash
#
# Download the LogDrop Taint analyzer for Android and check it before use.
#
#   LOGDROP_VERSION=v0.10.0 LOGDROP_DIR="$HOME/.logdrop" ./install-logdrop-taint.sh
#
# Nothing is compiled on your machine and no access to your source is needed: the jar
# arrives prebuilt. It runs on any JVM 17 or newer, which every machine that builds an
# Android app already has — the Android Gradle Plugin requires it.
set -euo pipefail

VERSION="${LOGDROP_VERSION:-v0.10.0}"
DIR="${LOGDROP_DIR:-$PWD/logdrop}"
REPO="initialcodess/logdrop-taint-android-action"
JAR="logdrop-taint-android-${VERSION}.jar"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid LOGDROP_VERSION: '$VERSION' (expected v1.2.3)" >&2
  exit 1
fi

# The JVM is the only requirement, so say so clearly rather than failing later with
# something about a class file version.
if ! command -v java >/dev/null 2>&1; then
  echo "java was not found. LogDrop Taint needs a JVM 17 or newer — the same one your" >&2
  echo "Android build already uses." >&2
  exit 1
fi
major=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
if [ "${major:-0}" -lt 17 ]; then
  echo "java $major found; LogDrop Taint needs 17 or newer." >&2
  exit 1
fi

mkdir -p "$DIR"

# Already downloaded and verified: nothing to do. This is what makes the step
# cacheable in CI without any special handling.
if [ -f "$DIR/$JAR" ] && [ -f "$DIR/$JAR.sha256" ] &&
   ( cd "$DIR" && shasum -a 256 -c "$JAR.sha256" >/dev/null 2>&1 ); then
  echo "Already present: $DIR/$JAR"
  exit 0
fi

BASE="https://github.com/${REPO}/releases/download/${VERSION}"
echo "Downloading $JAR"
curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$JAR" "$BASE/$JAR"
curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$JAR.sha256" "$BASE/$JAR.sha256"

# VERIFY BEFORE RUNNING. A jar that arrived altered or truncated must never scan: a
# corrupt one might merely crash, but an altered one is somebody else's code running
# over your source.
echo "Verifying integrity (SHA-256)"
( cd "$DIR" && shasum -a 256 -c "$JAR.sha256" )

echo "Installed: $DIR/$JAR ($(java -jar "$DIR/$JAR" --version))"
