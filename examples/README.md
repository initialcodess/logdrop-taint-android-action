# Integration recipes

LogDrop Taint is **not tied to GitHub.** The analyzer is a single jar and needs only
a JVM 17 or newer — no Android SDK, no Gradle, no macOS.

## The model: the same three steps everywhere

```
1. DOWNLOAD  →  once, per version (cacheable)
2. VERIFY    →  SHA-256; a corrupt or altered jar never scans
3. RUN       →  the exit code makes the decision
```

The first two live in [`install-logdrop-taint.sh`](install-logdrop-taint.sh), and
every recipe below calls it. On GitHub Actions you do not even need that — the
action does both for you.

## Sending the report to the panel

Optional, and off until you switch it on. Every recipe here ends by calling
[`report-to-panel.sh`](report-to-panel.sh), and the step is safe to leave in place:
with nothing configured it prints one line and does nothing.

Three variables, and you need all three:

| Variable | What it is |
|---|---|
| `PANEL_URL` | Your panel's address |
| `LOGDROP_LICENSE` | Your key — already required for the scan itself |
| `BUNDLE_ID` | Your application id, **as registered in the panel** |

Set them wherever your CI keeps configuration and reports start arriving; no edit to
the recipe. Miss one and nothing is sent, quietly — so if the dashboard stays empty,
check that all three are actually reaching the job.

**The bundle id must be registered for that project in the panel.** One the panel
does not recognise is refused outright, nothing is stored, and the step fails. That
is deliberate: a typo you can see beats a green pipeline that sent nothing.

**The analyzer itself never contacts anything.** It verifies its licence offline,
counts no usage and does not report that it ran. Sending is a separate step, on a
report that already exists, run by you — which is why it is a script you can read
rather than a flag inside the jar.

**A rejected report fails the build; a panel that is down does not.** If the panel
refuses the report — the usual cause is a `BUNDLE_ID` not registered for your
project — the step exits non-zero and you see it. A step that stayed green while no
report ever arrived is the failure nobody notices until someone asks why the
dashboard is empty.

If the panel is unreachable, under maintenance, or simply not configured, the step
exits 0 and your build is untouched. The scan's exit code already said what it
found, and a maintenance window on our side must not turn your green build red an
hour later. An expired or revoked licence is in this second group too: the
developer who pushed the commit cannot fix it, so it warns rather than blocks.

This script is the **twin of the one in the iOS repository** and is kept byte for
byte identical below its header. The panel has one endpoint and the report is the
same SARIF whichever analyzer produced it; a fix in one that did not reach the other
would leave two products disagreeing about how to talk to one server.

Which customer a report belongs to comes from your **licence key**, not from
anything the recipe sends.

## Exit codes — the contract every integration rests on

| Code | Meaning | What CI should do |
|---|---|---|
| `0` | Clean | Carry on |
| `1` | Findings (with `--fail-on-findings`) | Fail the build, block the pull request |
| `2` | Licence missing / invalid / expired | Fail, but DO NOT say "your code has a vulnerability" |
| `3` | An error in the arguments or `.logdrop.json` | Fail, fix the configuration |

Telling `1` and `2` apart matters: a developer whose licence lapsed will go looking
in entirely the wrong place if you tell them their code is insecure.

## The recipes

| System | File | Note |
|---|---|---|
| **GitHub Actions** | [main README](../README.md) | The action does everything, download and verification included |
| **CircleCI** | [`circleci/config.yml`](circleci/config.yml) | A plain Linux container; free on the free plan |
| **GitLab CI** | [`gitlab/.gitlab-ci.yml`](gitlab/.gitlab-ci.yml) | Any JDK 17 image |
| **Jenkins** | [`jenkins/Jenkinsfile`](jenkins/Jenkinsfile) | Any agent with a JVM |
| **Bitrise** | [`bitrise/bitrise.yml`](bitrise/bitrise.yml) | Runs on the Linux stack |
| **Gradle** | [`gradle/logdrop.gradle.kts`](gradle/logdrop.gradle.kts) | A task in your own build; scan before you push |

## Where the licence key goes

Always in the **`LOGDROP_LICENSE` environment variable**, and always sourced from
that system's secret store:

| System | Where |
|---|---|
| GitHub Actions | Repository secrets |
| CircleCI | Project Settings → Environment Variables |
| GitLab | Settings → CI/CD → Variables (tick **Masked**) |
| Jenkins | Credentials → Secret text |
| Bitrise | Secrets |
| Local | `export LOGDROP_LICENSE=...` or `~/.logdrop/license` |

Do not write the key into a configuration file: command-line arguments can show up
in run logs and in the process list, which is why every recipe here uses the
environment variable.

## No macOS, and that is the point

The iOS analyzer needs a Mac because it links against Apple system libraries. This
one does not: Kotlin and Java are parsed by a JVM library, so the scan runs in the
same cheap Linux container as the rest of your pipeline.

That matters on a bill. Cloud providers charge macOS roughly ten times Linux
(GitHub's published ratio); this half of the product costs the Linux rate, and on
the free tiers of most providers, nothing at all.

## Scanning from a developer machine

Point the same jar at your source before you push:

```bash
java -jar "$HOME/logdrop/logdrop-taint-android-v0.10.0.jar" app/src \
  --sarif logdrop-taint.sarif --verbose
```

Leave `--fail-on-findings` off locally. On your own machine this is a warning layer;
the gate belongs in CI, where it blocks the merge. A scan that broke the build every
time you typed a half-finished line would be turned off within a day.

The Gradle recipe wraps exactly this, so `./gradlew logdropScan` does the same thing
without remembering the path.
