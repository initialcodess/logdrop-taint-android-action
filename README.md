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

## Everywhere else

Working recipes under [`examples/`](examples): CircleCI, GitLab CI, Jenkins, Bitrise,
and a Gradle task for scanning from the developer's own machine. All of them are the
same three steps — download, verify, run.

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

Test code is skipped by default (`src/test`, `src/androidTest`, `*Test.kt`) and the
count is printed rather than passed over in silence.

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
