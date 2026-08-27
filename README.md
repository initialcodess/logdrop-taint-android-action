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
