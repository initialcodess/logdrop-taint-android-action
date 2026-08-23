#!/usr/bin/env bash
#
# Send a finished SARIF report to the LogDrop panel.
#
# WHY THIS IS A SEPARATE SCRIPT, AND NOT PART OF THE ANALYZER
#
# The analyzer contacts no server. It verifies its licence offline, counts no
# usage and tells nobody it ran — that is the product's central promise, and a
# scanner that phones home cannot make it. Reporting is therefore a step you can
# see, run by you, on a report that already exists.
#
# The GitHub Action does this same POST internally when you give it `panel-url`.
# Everywhere else — CircleCI, GitLab, Jenkins, Bitrise, a Gradle task, a laptop —
# this script is that step.
#
# THIS FILE IS A TWIN of the one in initialcodess/logdrop-taint-action, and the two
# must stay identical. The report is the same SARIF whichever analyzer produced it,
# and the panel has one endpoint, so a fix that lands on one side and not the other
# means two products disagreeing about how to talk to the same server.
#
# It is duplicated rather than shared because the Android recipes used to curl the
# iOS copy from that repository's MOVING `v1` tag. It worked — until iOS releases
# v2, or the script grows something iOS-specific, at which point Android breaks for
# a reason nobody would look for in an iOS changelog. `scripts/verify.sh` compares
# the two and fails when they drift.
#
# USAGE
#   PANEL_URL=https://panel.example.com \
#   LOGDROP_LICENSE="LOGDROP...." \
#   BUNDLE_ID=com.company.app \
#     ./report-to-panel.sh logdrop-taint.sarif
#
# WITHOUT PANEL_URL IT DOES NOTHING, and says so. Recipes can therefore include
# the step unconditionally: a customer who never sets PANEL_URL never sends
# anything, and one who sets it needs no further edits.
#
# EXIT CODE: whose problem is it?
#
#   Something you can fix   → 1, and your build goes red.
#   Something we broke, or  → 0, and your build is untouched.
#   a panel that is simply
#   not configured
#
# A wrong bundle id is the first kind. The panel refuses the report, nothing is
# stored, and if this script stayed quiet about it the step would sit there green
# while no report ever arrived — the failure mode nobody notices until someone asks
# why the dashboard is empty. So a rejection is a red build.
#
# A panel that is down, unreachable, or not configured at all is the second kind.
# The scan already ran and its exit code already said what it found; a maintenance
# window on our side must not turn a customer's green build red an hour later.
set -uo pipefail

SARIF="${1:-logdrop-taint.sarif}"

if [ -z "${PANEL_URL:-}" ]; then
  echo "LogDrop: PANEL_URL is not set — the report stays on this machine."
  exit 0
fi

if [ ! -f "$SARIF" ]; then
  echo "LogDrop: no report at '$SARIF' — nothing to send." >&2
  exit 0
fi

if [ -z "${LOGDROP_LICENSE:-}" ]; then
  echo "LogDrop: PANEL_URL is set but LOGDROP_LICENSE is not; the panel identifies you by your key." >&2
  exit 0
fi

if [ -z "${BUNDLE_ID:-}" ]; then
  echo "LogDrop: PANEL_URL is set but BUNDLE_ID is not; the panel needs it to know which app this is." >&2
  exit 0
fi

# Which app, which build. Everything here is optional context — the panel works
# without it, and reads WHICH CUSTOMER this belongs to from the licence key, not
# from anything sent here.
APP_NAME="${APP_NAME:-$(basename "$PWD")}"
VERSION="${VERSION:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
COMMIT="${COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"

URL="${PANEL_URL%/}/api/reports/sarif"
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

# No `|| echo 000` on the end of this: when curl cannot connect, -w already
# prints "000", and the two together produce "000000" — which matches no branch
# below, so an unreachable panel would fall through to the catch-all and report a
# nonsense status code.
CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer $LOGDROP_LICENSE" \
  -F "sarif=@$SARIF" \
  -F "bundle_id=$BUNDLE_ID" \
  -F "app_name=$APP_NAME" \
  -F "version=$VERSION" \
  -F "commit=$COMMIT")
CODE=${CODE:-000}

case "$CODE" in
  200|201)
    echo "LogDrop: report sent to the panel."
    exit 0
    ;;
  400|422)
    # The usual cause is a bundle id that is not registered for this project. The
    # panel says which one it did not recognise; it does not list the ones it knows,
    # on purpose — a CI log is not always private.
    echo "LogDrop: the panel rejected the report ($CODE): $(head -c 300 "$BODY")" >&2
    echo "        Check BUNDLE_ID. Nothing was stored." >&2
    exit 1
    ;;
  401)
    # A key the panel cannot read at all: the wrong secret, or one mangled in
    # copying. Whoever configured it can fix it, so it is worth stopping for.
    echo "LogDrop: the panel could not read the licence key (401)." >&2
    echo "        Check LOGDROP_LICENSE — a line break in the value is the usual cause." >&2
    exit 1
    ;;
  413)
    echo "LogDrop: the report exceeded the panel's size limit (413)." >&2
    echo "        Narrow the scan with 'exclude' in .logdrop.json." >&2
    exit 1
    ;;
  403)
    # Deliberately NOT a failure, unlike its 4xx neighbours. A 403 means the key is
    # recognised but no longer permitted — expired, or revoked. That is a commercial
    # matter between two companies, and the developer who pushed this commit can do
    # nothing about it. Failing their build over it punishes the wrong person, and
    # the analyzer already refuses to run on an expired key (exit 2) long before the
    # report gets this far.
    echo "LogDrop: the panel did not accept the licence (403): $(head -c 300 "$BODY")" >&2
    echo "        It may be expired or revoked — satis@initialcode.io" >&2
    exit 0
    ;;
  503)
    echo "LogDrop: the panel is unavailable (503). The scan was unaffected." >&2
    exit 0
    ;;
  000)
    echo "LogDrop: the panel could not be reached ($PANEL_URL). The scan was unaffected." >&2
    exit 0
    ;;
  *)
    # An unfamiliar code is not evidence that the customer did anything wrong.
    echo "LogDrop: the panel returned $CODE: $(head -c 300 "$BODY")" >&2
    exit 0
    ;;
esac
