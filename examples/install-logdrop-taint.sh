#!/usr/bin/env bash
#
# Download the LogDrop Taint analyzer for Android and check it before use.
#
#   LOGDROP_VERSION=v1.0.2 LOGDROP_DIR="$HOME/.logdrop" ./install-logdrop-taint.sh
#
# Nothing is compiled on your machine and no access to your source is needed: the jar
# arrives prebuilt. It runs on any JVM 17 or newer, which every machine that builds an
# Android app already has — the Android Gradle Plugin requires it.
set -euo pipefail

VERSION="${LOGDROP_VERSION:-v1.0.2}"
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

# EXPECTED CHECKSUMS — and the whole point is WHERE this table lives.
#
# The jar used to be checked against a .sha256 downloaded from the same release. That
# proves a download did not arrive corrupt, and nothing more: whoever can replace the
# jar in a release can replace the checksum beside it, and the check still passes. A
# verifier that ships with the thing it verifies is not a verifier.
#
# So the expected value lives HERE, in the script the customer already pinned. Pin the
# action by commit SHA and this line is fixed at that commit: swapping the release is
# no longer enough, because the attacker would also have to change a commit you have
# named. That is why the README asks for a SHA rather than @v1.
#
# It does not defend against someone who can push to THIS repository. Nothing in a
# repository can. Pinning is what limits that, and it is the customer's move.
expected_sha() {
  case "$1" in
    v1.0.2) echo "503db287b4f31c8f1d13474563b1f63387b3aa9fa46f7959438cc6284b35f091" ;;
    *)      echo "" ;;
  esac
}
EXPECTED="$(expected_sha "$VERSION")"

# STRICT MODE, checked BEFORE anything is fetched. Same shape as fail-on-findings and
# fail-on-delivery-error: advisory by default, hard gate on request, because the
# default that serves the most people is the one that does not break a pipeline over
# something its owner cannot fix today. Refusing after a 60 MB download would be the
# same answer, later and more expensively.
if [ -z "$EXPECTED" ] && [ "${LOGDROP_REQUIRE_PINNED_CHECKSUM:-false}" = "true" ]; then
  echo "" >&2
  echo "  NO PINNED CHECKSUM for $VERSION, and one was required." >&2
  echo "  This installer carries checksums for the versions it shipped with. Either" >&2
  echo "  ask for a version it knows, or move to an action release that carries" >&2
  echo "  $VERSION. Nothing was downloaded." >&2
  echo "" >&2
  exit 1
fi

mkdir -p "$DIR"

# Already downloaded and verified: nothing to do. This is what makes the step
# cacheable in CI without any special handling. The cached copy is re-checked against
# the same expected value, so a tampered cache does not survive either.
if [ -f "$DIR/$JAR" ] && [ -n "$EXPECTED" ] &&
   [ "$(shasum -a 256 "$DIR/$JAR" | cut -d" " -f1)" = "$EXPECTED" ]; then
  echo "Already present: $DIR/$JAR"
  exit 0
fi

BASE="https://github.com/${REPO}/releases/download/${VERSION}"
echo "Downloading $JAR"
curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$JAR" "$BASE/$JAR"

# VERIFY BEFORE RUNNING. An altered jar is somebody else's code running over your
# source; a truncated one would merely crash, later and less usefully.
actual="$(shasum -a 256 "$DIR/$JAR" | cut -d' ' -f1)"

if [ -n "$EXPECTED" ]; then
  echo "Verifying against the checksum shipped with this action (SHA-256)"
  if [ "$actual" != "$EXPECTED" ]; then
    echo "" >&2
    echo "  CHECKSUM MISMATCH — the jar was NOT what this action expects." >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $actual" >&2
    echo "  Nothing was run. Do not use this jar." >&2
    echo "" >&2
    rm -f "$DIR/$JAR"
    exit 1
  fi
else
  # A version this copy of the script does not know — an older pinned action asked for
  # a newer analyzer. Falling back keeps that working, but it is a WEAKER check and
  # says so rather than letting the output imply otherwise.
  #
  curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$JAR.sha256" "$BASE/$JAR.sha256"

  # On GitHub the log body is where warnings go to be missed; an annotation is
  # collected at the top of the run. Guarded, because this same script runs on
  # CircleCI, GitLab, Jenkins and Bitrise, where the syntax would be noise.
  weak="This action carries no checksum for $VERSION, so the jar was checked against the checksum published beside it. That detects a corrupt download, not a replaced one — both come from the same release. Pin an action version that knows $VERSION, or set require-pinned-checksum to fail instead."
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning title=Weak integrity check::$weak" >&2
  fi
  echo "This action does not carry a checksum for $VERSION."
  echo "Falling back to the checksum published beside the jar: this detects a corrupt"
  echo "download, but NOT a replaced one, because both come from the same release."
  ( cd "$DIR" && shasum -a 256 -c "$JAR.sha256" )
fi

echo "Installed: $DIR/$JAR ($(java -jar "$DIR/$JAR" --version))"
