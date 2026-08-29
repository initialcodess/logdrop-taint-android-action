# LogDrop Taint (Android)

Taint (data-flow) analysis for **Android source — Kotlin and Java**, emitting **SARIF 2.1.0**.

It follows a value from a *source* — what the user typed, what another app sent through
an Intent, what a server returned, a constant in the code — to a *sink*, and reports the
ones that arrive unsanitised carrying a label that sink accepts.

The iOS counterpart is
[logdrop-taint-action](https://github.com/initialcodess/logdrop-taint-action). Both
produce the same report shape, so a repository running each sees one kind of finding.

## Your source never leaves the machine

The analyzer **opens no network connection**. Not for licensing, not for usage
counting, not to say it ran. The licence is verified offline by signature — counting
how many repositories you scan would require a connection, so we do not count.

A report carries the rule, the file, the line, and by default the offending line with
two either side. Never the file, never the rest of your code. `snippets: "false"`
removes even that.

Sending a report to a panel is a **separate step you run**, off unless you switch it on.

## GitHub Actions

```yaml
name: Security scan
on: [pull_request]

jobs:
  taint:
    runs-on: ubuntu-latest        # Linux. No Mac, no Android SDK.
    permissions:
      contents: read
      security-events: write      # only if you upload to Code Scanning
    steps:
      - uses: actions/checkout@v4
      - uses: initialcodess/logdrop-taint-android-action@v0
        with:
          license: ${{ secrets.LOGDROP_LICENSE }}
          path: app/src
          fail-on-findings: "true"
```

Findings appear three ways, all free on every plan: a box above the line in *Files
changed*, a table in the job summary, and the failed check that blocks the merge.

## Using it without GitHub (your machine, your server)

The analyzer is **a single jar** and needs only a JVM — no Android SDK, no Gradle,
no macOS. So you are not tied to GitHub Actions:

```bash
# Download and verify it once (change the version as needed)
V=v0.8.0
curl -fsSL -o install.sh \
  "https://raw.githubusercontent.com/initialcodess/logdrop-taint-android-action/$V/examples/install-logdrop-taint.sh"
chmod +x install.sh
LOGDROP_VERSION=$V LOGDROP_DIR="$HOME/logdrop" ./install.sh   # checks the SHA-256

# Run it
export LOGDROP_LICENSE="LOGDROP...."
java -jar "$HOME/logdrop/logdrop-taint-android-$V.jar" app/src \
  --sarif report.sarif --verbose --fail-on-findings
```

Where that helps:

- **On a developer machine** — scan your own code before you push.
- **On your own build server** (Jenkins, TeamCity, Bitrise, a spare box): the two
  commands above are the whole build step. Exit code `1` means findings.
- **As a Gradle task** — see [`examples/gradle`](examples/gradle).
- **On a self-hosted runner** — this action works as-is.

The `--sarif` output is standard SARIF 2.1.0; open it in a SARIF viewer or feed it
into your own dashboard.

**Ready-made recipes:** [`examples/`](examples) has working setups for CircleCI,
GitLab CI, Jenkins, Bitrise and Gradle — all built on the same install script.

## Where you see the findings

All three are **free and work on every GitHub plan**:

1. **An inline box on the pull request** — the finding appears above the relevant
   line in the "Files changed" view.
2. **The job summary** — a location / rule / finding table on the run page.
3. **The CI gate** — with `fail-on-findings: "true"`, findings block the merge.

If **Code Scanning** is enabled on your repository, the SARIF is uploaded there as
well. That feature is free on public repositories and depends on GitHub's paid Code
Security licence on private ones; without a licence the step warns and moves on —
it **does not break the build**.

## Test code is skipped

Test fixtures are where fake credentials live, and nothing in the code distinguishes
`password = "test"` in a test helper from the real thing — same write, same type,
same field name. Files under `src/test` or `src/androidTest`, or named `*Test.kt` /
`*Test.java`, are left out by default.

It is not done quietly — the step prints what it skipped:

```
Skipped 214 test file(s). Use --include-tests to scan them.
```

A file named directly on the command line is always scanned, whatever it is called.
Set `include-tests: "true"` to scan them anyway.

## What it finds

| Scenario | CWE |
|---|---|
| User, network or Intent data reaches a `WebView` unsanitised | CWE-79 |
| User or network data is concatenated into a SQL query | CWE-89 |
| Personal data is written to the log | CWE-532 |
| Personal data or credentials go into local storage in the clear — `SharedPreferences`, DataStore, Room, a SQLite row, a file | CWE-312 |
| A key hardcoded in the source reaches `SecretKeySpec` | CWE-321 |
| Personal data or a credential is copied to the clipboard | CWE-200 |
| User or network data is built into a selection clause instead of `selectionArgs` | CWE-943 |

`EncryptedSharedPreferences` is the **fix**, not the bug, and is never reported — even
though it is used through exactly the same `edit().putString(...)` calls.

What a value is also comes from the name it is read from: `cvvEditText.text` is a
CVV, while `searchEditText.text` is only user input and produces nothing — logging
your own search term is not a leak.

It follows flows across functions and across files, and does not report data that
passed through a sanitiser. Sanitising is **label-specific**: escaping HTML stops
the injection but does not stop the data being personal — an escaped email written
to the log is still a finding.

## Sending reports to the LogDrop panel (optional)

If you want to track findings over time, see the binary (Layer 1) and source scans
for the same app on one screen, and carry "this is a false positive" decisions
across scans, you can send the report to the panel:

```yaml
- uses: initialcodess/logdrop-taint-android-action@v0
  with:
    license: ${{ secrets.LOGDROP_LICENSE }}
    path: app/src
    bundle-id: com.company.app           # required when sending to the panel
    panel-url: https://panel.logdrop.io
```

**Off by default.** Without `panel-url` nothing is sent and the scan stays entirely
local.

Sending needs three things together — `panel-url`, `license` and `bundle-id`. Miss
any one and nothing is sent. **`bundle-id` must be the id registered for that
project in the panel**: an id the panel does not recognise is refused and the step
fails, so a typo is loud rather than silent.

Not on GitHub Actions? Every recipe under [`examples/`](examples) ends by calling
[`examples/report-to-panel.sh`](examples/report-to-panel.sh), which does the same
POST from CircleCI, GitLab, Jenkins, Bitrise or a laptop. It does nothing until you
set all three of `PANEL_URL`, `LOGDROP_LICENSE` and `BUNDLE_ID`. If the panel
*rejects* a report — usually a bundle id not registered for your project — the step
fails, because a green step that sent nothing is worse than a red one. If the panel
is merely unreachable, it warns and your build is untouched.

The analyzer itself still contacts nothing: sending is a separate step on a report
that already exists, which is what keeps "the scanner never phones home" true
wherever you run it.

When it is sent, the only thing that goes is the **SARIF**: rule id, file path, line
number and (if enabled) the code of the offending line — so the panel can show the
faulty code with the relevant line highlighted. Turn the snippets off with
`snippets: "false"`, or stop the sending altogether by leaving `panel-url` unset.

Which customer a report belongs to comes from your **licence key**, not from
anything the recipe sends.

## Adapting it to your codebase

Put a `.logdrop.json` at your repository root to teach the analyzer about **your**
code — your sanitising function, your field names, your logging wrapper.

```json
{
  "sanitizers":     { "makeSafe": ["user-input"], "maskEmail": ["pii"] },
  "sources":        { "nationalId": "pii", "customerEmail": "pii" },
  "sensitiveNames": { "sifre": "pii", "kartNo": "pii" },
  "sinks":          { "secret": { "rule": "ANDROID-TAINT-PII-LOG", "accepts": ["pii"] } },
  "passthrough":    ["normalise"],
  "exclude":        ["vendor/", "generated/"]
}
```

| Field | What it does |
|---|---|
| `sanitizers` | Your own sanitising function; state which kind of taint it removes. No finding is produced past it. |
| `sources` | Your own personal-data fields (`nationalId` and the like). |
| `sensitiveNames` | Your own names for sensitive inputs. A value read from a name listed here counts as personal data — useful when your fields are not in English. |
| `sinks` | Your own wrapper (your logging class, say) — state which rule it maps to. |
| `passthrough` | Your own helpers that transform data but preserve taint. |
| `exclude` | Paths to skip. A path is skipped if it contains the fragment. |

Labels: `user-input`, `hardcoded-secret`, `pii`, `credential`.

A bad config is **not ignored silently**: an unrecognised field, rule or label is
rejected before the scan starts (exit `3`), and the message lists the valid ones.
Silently ignoring it would leave you believing a setting is in force when it never
was.

## Silencing a finding you have judged

Sometimes a finding is real code and still not a problem for you. You should be able
to say so once and not be asked again.

That judgement lives in `.logdrop-suppressions.json` at your repository root, and it
is **written and signed by the LogDrop panel**. The analyzer verifies the signature
offline — it contacts nothing, here or anywhere else — and honours nothing it cannot
verify.

```json
{
  "version": 1,
  "suppressions": [
    {
      "fingerprint": "a3f1c0d92b74e518",
      "reason": "Test double; this password is not a real one",
      "by": "ayse@example.com",
      "at": "2026-08-26"
    }
  ],
  "signature": "…"
}
```

**Why signed rather than a file you write yourself.** Not to make it hard for you —
if you want the scan gone you can delete this step in one line. It is so that
silencing a finding costs a moment of thought. An unsigned file gets a line appended
the first time a build goes red, by whoever is in a hurry; nobody reviews it, and a
real leak gets silenced with the same keystroke as a false alarm. Going through the
panel means somebody said why, and it is written down.

The file stays readable and stays in your repository, so anyone reviewing a pull
request can see what is being silenced and object to it.

**What the signature covers:** which findings are silenced, and the expiry. It does
**not** cover `reason`, `by` or `at` — those are for whoever reads the diff, and
fixing a typo in a sentence must not invalidate the file.

**One file covers both platforms.** If you ship an iOS app too, the same panel signs
one file that both analyzers accept.

**A silenced finding is not deleted.** It stays in the report, marked as suppressed
with your reason attached, so GitHub Code Scanning and the panel show it as closed
rather than as never having existed. The count says so plainly:

```
LogDrop Taint: 4 finding(s) (1 suppressed) → logdrop-taint.sarif
```

It does not fail the build.

**If the file cannot be verified, it is ignored and every finding is reported** — and
the reason is printed. A hand-edited file, a file signed with the wrong key, an
expired one: all of them say so out loud. Believing a finding is silenced when it is
not is the one outcome worth protecting you from.

**A judgement is about a line, not a line number.** Moving code around, adding an
import, reformatting: the suppression holds. Editing the offending line itself
releases it, and that is deliberate — the code you judged is no longer the code that
is there.

> **Not `exclude`.** `exclude` in `.logdrop.json` drops whole paths from the scan,
> unsigned, with nobody named. Used to clear one finding it also silences every
> future finding in that file, and nobody notices. It is for code that is not yours —
> vendored dependencies and the like. Every scan prints how many files it dropped and
> why, so a list that grows during a red build shows up in the log.

## Inputs

| Input | Default | Description |
|---|---|---|
| `license` | — | **Required.** Your licence key; keep it in a secret. |
| `path` | `.` | The file or directory to scan. |
| `fail-on-findings` | `false` | Fail the step when there are findings. |
| `annotations` | `true` | Inline boxes on the pull request. |
| `snippets` | `true` | The offending line plus ±2 lines of context in the report. With `false`, no fragment of your code leaves. |
| `include-tests` | `false` | Scan test code as well. Off by default — see [Test code is skipped](#test-code-is-skipped). |
| `upload-sarif` | `true` | Attempt to upload to Code Scanning. |
| `sarif-file` | `logdrop-taint.sarif` | SARIF output path. |
| `repo-root` | `github.workspace` | The root SARIF paths are relative to. |
| `panel-url` | *(empty)* | The panel address, if reports should go to the LogDrop panel. **Empty means nothing is sent.** |
| `bundle-id` | *(empty)* | The application id. Required when `panel-url` is set. |
| `analyzer-version` | the version tested with this release | You should not need to change it. |

**Outputs:** `findings` (the count), `sarif-file`.

## Exit codes — the contract every integration rests on

| Code | Meaning | What CI should do |
|---|---|---|
| `0` | Clean | Carry on |
| `1` | Findings (with `--fail-on-findings`) | Fail the build, block the pull request |
| `2` | Licence missing / invalid / expired | Fail, but DO NOT say "your code has a vulnerability" |
| `3` | An error in the arguments or `.logdrop.json` | Fail, fix the configuration |

Telling `1` and `2` apart matters: a developer whose licence lapsed will go looking in
entirely the wrong place if you tell them their code is insecure.

## Requirements

A **JVM 17 or newer** — the same one your Android build already uses, since the Android
Gradle Plugin requires it. No Android SDK, no Gradle, no macOS.

That last one is the difference from the iOS analyzer, which needs a Mac and is billed
at ten times the rate. This runs on the cheapest Linux runner there is.

## Licence

LogDrop Taint is **commercial software** and runs on a time-limited key. This
repository distributes the action and the compiled analyzer — it is not open
source, and the analyzer's source code is not in this repository.

The key is verified **offline**: the program contacts no server, does not count your
usage and reports to nobody. It warns 14 days before expiry.

To obtain a key: **satis@initialcode.io**

---
*Initial Code Software Solutions*
