# Contributing to AirSign

Thanks for helping. Bug reports, fixes, tests and documentation are all welcome. For anything security-related, follow [SECURITY.md](SECURITY.md) instead of opening an issue. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## What you need

- A Mac with Apple silicon and macOS 14 or later
- Xcode 16 or later (Swift 6 toolchain)
- AirPods with head tracking, only to run the app; `swift test` doesn't need them

## Build and test

```bash
cd airsign
swift test                         # the core: matcher, crypto, file locking, lockout
scripts/check.sh                   # run before opening a pull request
scripts/install.sh                 # builds, signs, installs to ~/Applications, registers the Finder items
AIRSIGN_ADHOC=1 scripts/install.sh # without an Apple Development certificate
```

With ad-hoc signing (`AIRSIGN_ADHOC=1`), macOS may ask for your password after each rebuild before AirSign can read its Keychain items. An Apple Development certificate avoids that: Xcode → Settings → Accounts → Manage Certificates → + → Apple Development.

## Continuous integration

Every pull request and every push to `main` runs `airsign/scripts/check.sh --with-test-volume` on `macos-26` with Xcode 26.5. The script checks:

- Debug, release and lab release builds have no warnings.
- Tests pass with coverage enabled.
- The README's test count matches the run, including skipped tests, and only known skips are allowed.
- `AirSignCore` line coverage is at least 85%.
- Ad-hoc signed app bundles have none of `--test-mode`, `--probe` and `--selftest-keychain` in the default build and all three in the lab build.
- Tracked files outside `docs/superpowers/` contain no machine paths.

Without `--with-test-volume`, the exFAT test is skipped locally. The replay test is skipped wherever the recordings are absent.

## Lab build

A lab build adds the test lab behind `--test-mode`, the AirPods probe (`--probe`), the Keychain self-test (`--selftest-keychain`) and its clean-up command (`--selftest-keychain-clean`). From `airsign/`, build one with `AIRSIGN_LAB=1 scripts/build-app.sh`, or use `swift run` for a debug build. Its window title says "AirSign (lab build)". Add `AIRSIGN_ADHOC=1` when building without an Apple Development certificate.

The test lab shows scores and writes raw signature motion in plaintext to the logs folder, `~/Library/Application Support/AirSign/test-logs`. It is for evaluation only, never for a Mac whose files matter. Never commit its logs or send them with a report.

Set `AIRSIGN_SANDBOX=<folder>` when launching a lab build to keep its profile in that folder and its keys under the separate Keychain service `com.makeuc.airsign.sandbox`. The banner shows `Sandbox data: <path>` even without `--test-mode`. For example, from `airsign/` run `AIRSIGN_SANDBOX=/tmp/airsign-lab swift run AirSign --test-mode`. Use that sandbox to try enrollment, the blocking screen and Reset without touching a real profile. After enrolling, quit the lab app and move the sandbox's `profile.bin` aside to try first run again, or remove only its `profile-key` Keychain item to try the blocking screen and Reset. All sandbox folders share this Keychain service. The test lab's plaintext logs still go to the logs folder above.

To remove the sandbox's Keychain items, quit the lab app and run the uninstall clean-up loop with its service. Files locked with sandbox keys then need their recovery code.

```bash
for account in profile-key master-key paired-recovery-keys lockout selftest; do
  security delete-generic-password -s com.makeuc.airsign.sandbox -a "$account" >/dev/null
done
```

An item-not-found error is fine when the sandbox never created that item. `AIRSIGN_SANDBOX=/tmp/airsign-lab swift run AirSign --selftest-keychain-clean` removes only the sandbox's self-test item.

## Where things are

| Path | What it is |
|---|---|
| `airsign/Sources/AirSignCore` | Pure logic with no UI: matcher, crypto, file format, lockout. Tested with Swift Testing in `airsign/Tests/AirSignCoreTests` |
| `airsign/Sources/AirSignLab` | The test lab's plaintext attempt log; only lab builds use it. Tested in `airsign/Tests/AirSignLabTests` |
| `airsign/Sources/AirSign` | The SwiftUI app: motion input, AirPods identity, Keychain, Finder Services, views |
| `airsign/Tests/AirSignTestSupport` | Helpers shared by the test targets |
| `tools/tuning` | Python port of the matcher for research. Tests: `cd tools/tuning && python3 -m unittest` (needs numpy) |
| `archive/makeuc-2026` | Hackathon records; not maintained |

## Rules for changes

- Write the test first for any change to `AirSignCore`, and keep `scripts/check.sh` passing.
- One topic per pull request. Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Update the README when behaviour that users see changes.
- Never commit signature recordings, test-lab logs, `profile.bin` or recovery codes. They are personal data or secrets.
- Don't change these without a migration, or existing users lose access to their files: the `.airsign` magic `AIRSIGN1`, the HPKE info string `airsign-file-v1`, the HKDF salt in `RecoveryCode.swift`, the Keychain service `com.makeuc.airsign` and the bundle id `com.makeuc.airsign`.
- Set your git email to your GitHub noreply address if you don't want your email in the history (GitHub → Settings → Emails).
