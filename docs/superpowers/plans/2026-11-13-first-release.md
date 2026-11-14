# First release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the first release, `0.1.0`, needs is in the repository and checked: the version, a changelog, documents that point at the tag, a written release procedure and a script that refuses to release from the wrong state.

**Architecture:** Two tasks in one pull request. The first sets the version and writes the texts. The second adds `release-check.sh`, which reads those texts, and the procedure that uses it. Publishing (the tag and the GitHub Release) is not a task: it happens on `main` after this pull request and pull request #18 have merged, with the maintainer's OK.

**Tech Stack:** Markdown, bash (must run under macOS's `/bin/bash` 3.2), `git`, `gh`, `/usr/libexec/PlistBuddy`.

**Spec:** `docs/superpowers/specs/2026-11-13-release-design.md`.

## Global Constraints

- The version is `0.1.0`; the tag will be `v0.1.0`. `CFBundleVersion` stays `1`.
- Nothing in the app's behaviour, wording or screens changes. `airsign/scripts/check.sh` does not change and keeps passing; `README.md` still has exactly one place where a number is followed by ` unit tests`.
- Every statement in the changelog and the notes is true of the code at the tag and promises nothing `SECURITY.md` does not. Where `SECURITY.md` qualifies a property, the changelog qualifies it the same way.
- The changelog describes pull request #18 (the rules move into the core library; file work runs in the background), which is not on this branch: it merges before the release. Its facts are in the pull request description the controller supplies.
- English, plain words, short sentences, like the documents already there. Say each thing once. No machine paths. No real tester names. Never read anything under `.local/`.
- No test, check or script touches the real Keychain items or the real Application Support folder. Nobody launches the built app from a script. The release check changes no tracked file and publishes nothing.
- Commit prefixes `docs:`, `chore:`, `ci:`; no attribution lines. Pushing the tag and creating the GitHub Release are not part of any task.

## Review Focus

1. **Claims.** A sentence in the changelog or the notes that says more than the code or `SECURITY.md` does (for example "restores are all-or-nothing" without the exception for exFAT and FAT, or "the lockout can't be ended by changing the clock" without "while the Mac has not restarted").
2. **The wrong state.** `release-check.sh` run on a branch, on a dirty tree, with a version that is not the one in `Info.plist`, with entries left under `Unreleased`, or when the tag already exists: each fails with its own name, before anything slow runs. Pinned in Task 2, step 4.
3. **A user following the README.** The install commands, copied as they are, clone the tag and build. They cannot work before the tag exists; the order in `docs/RELEASING.md` keeps that gap short and the pull request says so.
4. **The notes.** They are the changelog section plus fixed text, with nothing lost or doubled at the seams (no second title, no `Unreleased` text, no link definitions).
5. **No network, no `gh`.** The release check says which of the two is missing and stops; it does not pass, and it does not fail with a raw error.

---

### Task 1: The version, the changelog and the documents that point at the release

**Files:**
- Modify: `airsign/Resources/Info.plist` (`CFBundleShortVersionString`)
- Create: `CHANGELOG.md`
- Modify: `README.md` (one badge; the Install section), `SECURITY.md` ("Supported versions"), `CONTRIBUTING.md` (one rule), `.github/PULL_REQUEST_TEMPLATE.md` (one item)

**Interfaces:**
- Produces: `CHANGELOG.md` with exactly this skeleton, which Task 2's script reads:

```markdown
# Changelog

What changed in each release of AirSign, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semantic versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-13

…

[Unreleased]: https://github.com/eric20041027/AirSign/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/eric20041027/AirSign/releases/tag/v0.1.0
```

- [ ] **Step 1: The version.** `CFBundleShortVersionString` becomes `0.1.0`. Nothing else in `Info.plist` changes.

- [ ] **Step 2: `CHANGELOG.md`.** The `0.1.0` section, under the headings it needs out of Added, Changed, Fixed, Security, in this order of content:
  - One short paragraph: the first release; what AirSign does (lock a file or folder on a Mac with a signature drawn in the air with one AirPod; a recovery code as the way back; nothing leaves the Mac); built from source.
  - What changed since the state reviewed on 9 November 2026 (commit 5ca039a), from pull requests #16, #17 and #18, each checked against the code and against `SECURITY.md`:
    - a restored file or folder appears whole or not at all, with the exception `SECURITY.md` gives for drives that cannot rename without replacing; leftovers of an interrupted restore are cleaned up;
    - an unreadable profile or key never costs the master key: a blocking screen instead of "enroll again", and Reset replaces nothing until the new enrollment is saved;
    - changing the clock no longer ends a cooldown while the Mac has not restarted; a missing Keychain copy of the lockout starts the longest cooldown;
    - the test lab, the AirPods probe and the Keychain self-test are only in lab builds;
    - pairing a second Mac is described in the security model;
    - saving the profile can't half-succeed; a lockout saved by an older build can't outlast 4 hours; "Forget paired Macs" works when the pairing keys can't be read;
    - locking and unlocking run in the background, one operation at a time, with a progress line; items opened meanwhile wait their turn.
  - "Upgrading from a build made before 13 November 2026": the one-time 4-hour cooldown when the Keychain has no `lockout` item, the command that tells (`security find-generic-password -s com.makeuc.airsign -a lockout`), and what to do (unlock one file with the old build first).
  - One line pointing at "Known limitations" in `SECURITY.md`. The limits are not repeated.
  Do not mention CI, tests, refactoring or anything else a user of the app would not notice.

- [ ] **Step 3: `README.md`.** After the CI badge add a release badge: image `https://img.shields.io/github/v/release/eric20041027/AirSign?color=1a5cff`, linked to `https://github.com/eric20041027/AirSign/releases/latest`. In "Install", the first command becomes `git clone --branch v0.1.0 --depth 1 https://github.com/eric20041027/AirSign.git`. Add one sentence: there is no prebuilt app, because a download that opens with a double-click needs an Apple Developer ID certificate and notarization, which this project does not have; AirSign is built from source and signed on your own Mac. Add one line for the newest code: clone without `--branch v0.1.0`. Everything else in the section stays.

- [ ] **Step 4: `SECURITY.md`, `CONTRIBUTING.md`, the PR template.** "Supported versions" says: security fixes go to the latest release and to `main`; older releases get none. In CONTRIBUTING's rules, after the README rule: "Add a line under Unreleased in `CHANGELOG.md` when a user would notice the change." The PR template gains, after the README item: `- [ ] CHANGELOG.md has a line under Unreleased if a user would notice the change`.

- [ ] **Step 5: Verify.**

Run: `airsign/scripts/check.sh && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' airsign/Resources/Info.plist && grep -n '^## \[' CHANGELOG.md && grep -c '[0-9] unit tests' README.md`
Expected: `All checks passed.`; `0.1.0`; the two headings `## [Unreleased]` and `## [0.1.0] - 2026-11-13`; `1`.

- [ ] **Step 6: Commit.**

```bash
git add airsign/Resources/Info.plist CHANGELOG.md README.md SECURITY.md CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs: version 0.1.0, a changelog, and install steps that point at the tag"
```

---

### Task 2: `release-check.sh` and the written procedure

**Files:**
- Create: `airsign/scripts/release-check.sh` (executable)
- Create: `docs/RELEASING.md`
- Modify: `CONTRIBUTING.md` (one line pointing at `docs/RELEASING.md`)

**Interfaces:**
- Consumes: the skeleton of `CHANGELOG.md` from Task 1; `airsign/scripts/check.sh --with-test-volume`.
- Produces: `airsign/scripts/release-check.sh <version> [--notes <file> | --preview-notes <file>]`.
  - `<version>` has the form `X.Y.Z`.
  - On the first problem it prints `release check failed: <name>` and one line saying why, to stderr, and exits non-zero. On success its last line is `Ready to release <version> from <short commit>.`
  - The checks, in this order, with their names:

| # | Name | Passes when |
|---|---|---|
| 1 | `usage` | the arguments have the form above |
| 2 | `version` | `CFBundleShortVersionString` in `airsign/Resources/Info.plist` equals `<version>` |
| 3 | `changelog` | `CHANGELOG.md` has a heading `## [<version>] - YYYY-MM-DD`, and nothing but blank lines between `## [Unreleased]` and the next `## ` heading |
| 4 | `working tree` | `git status --porcelain` prints nothing |
| 5 | `branch` | the current branch is `main` and its commit is the one `origin`'s `main` points at now (asked from the remote without fetching) |
| 6 | `tag` | `v<version>` exists neither locally nor on `origin` |
| 7 | `ci` | on that commit, the check run named `check` finished with success (asked through `gh`) |
| 8 | `checks` | `airsign/scripts/check.sh --with-test-volume` passes |

  - Checks 5 to 7 need the network, and 7 needs `gh`: when one is missing the failure is `release check failed: network` or `release check failed: gh`, with one line saying what to do.
  - `--notes <file>`: after all eight checks pass, writes the release notes to `<file>`.
  - `--preview-notes <file>`: after checks 1 to 3 only, writes the same notes to `<file>` and ends with `Notes written to <file>. This was a preview: the release was not checked.` It is how a pull request shows the notes before anything can be released.
  - The notes: the body of the changelog's section for `<version>` (without its heading and without the link definitions at the end of the file); then `## Install` with what is needed (a Mac with Apple silicon, macOS 14 or later, AirPods with head tracking, Xcode 16 or later) and the commands to clone the tag `v<version>` and run `scripts/install.sh`, with the ad-hoc line; then `## Why there is no app to download`, the one paragraph from the spec. The fixed text lives in the script.
  - It works from any current directory, changes no tracked file, and never pushes, tags or publishes.

- [ ] **Step 1: Write `release-check.sh`** as described, with `set -euo pipefail`.

- [ ] **Step 2: Preview the notes and read them.**

Run: `airsign/scripts/release-check.sh 0.1.0 --preview-notes /tmp/airsign-notes.md && sed -n '1,12p' /tmp/airsign-notes.md && grep -c '^\[Unreleased\]\|^\[0.1.0\]\|^## \[' /tmp/airsign-notes.md`
Expected: the preview line; the notes start with the changelog section's first heading or paragraph, not with `## [0.1.0]`; the `grep` prints `0`.

- [ ] **Step 3: Run it for real on this branch.**

Run: `airsign/scripts/release-check.sh 0.1.0; echo "exit=$?"`
Expected: `release check failed: branch` (checks 1 to 4 passed; this is not `main`), `exit=1`. Nothing slow ran.

- [ ] **Step 4: Make the early checks fail once each.** One at a time, with the tree otherwise clean, make the change, run the command, confirm the name, undo the change; `git status --short` is clean at the end.

| Temporary change or command | Expected |
|---|---|
| `release-check.sh` with no argument; with `0.1`; with `0.1.0 --bogus` | `release check failed: usage` |
| `release-check.sh 0.1.1` | `release check failed: version` |
| in `CHANGELOG.md`, change `## [0.1.0] - 2026-11-13` to `## [0.1.0]` | `release check failed: changelog` |
| in `CHANGELOG.md`, add the line `- something` under `## [Unreleased]` | `release check failed: changelog` |
| create an untracked file `airsign/x.tmp` | `release check failed: working tree` |
| create the local tag `v0.1.0` on a copy of the repository whose branch is renamed `main`, with no remote | `release check failed: network` or `branch` (it must not pass and must not print a raw error); delete the copy |

- [ ] **Step 5: `docs/RELEASING.md`.** The steps, in order, with the exact commands, for a maintainer:
  1. Choose the version (semantic versioning; below 1.0 the file format and the Keychain items still don't change without a migration).
  2. On a branch: move what is under `Unreleased` in `CHANGELOG.md` into a new section `## [X.Y.Z] - <today>`, add its link definition and update the `Unreleased` one; set `CFBundleShortVersionString`; change the tag in the README's install command; open a pull request. Show the notes in it with `--preview-notes`.
  3. After it merges: `git checkout main && git pull --ff-only`, then `airsign/scripts/release-check.sh X.Y.Z --notes <file>`.
  4. Tag and push: `git tag -a vX.Y.Z -m "AirSign X.Y.Z"` and `git push origin vX.Y.Z`.
  5. Create the release: `gh release create vX.Y.Z --title "AirSign X.Y.Z" --notes-file <file> --verify-tag --latest`.
  6. Look at the release page and at the README badge.
  It says that steps 4 and 5 are a maintainer's own decision each time, that nothing is attached to a release and why, and that the date in the changelog is not corrected after the merge.
  In `CONTRIBUTING.md`, one line after the table of folders: maintainers cut releases as described in `docs/RELEASING.md`.

- [ ] **Step 6: Verify.**

Run: `airsign/scripts/check.sh && bash -n airsign/scripts/release-check.sh && /bin/bash -n airsign/scripts/release-check.sh && git status --short`
Expected: `All checks passed.`; both syntax checks pass; the tree is clean apart from this task's files.

- [ ] **Step 7: Commit.**

```bash
git add airsign/scripts/release-check.sh docs/RELEASING.md CONTRIBUTING.md
git commit -m "ci: add release-check.sh and write down how a release is made"
```

---

## After the tasks (the controller)

1. Whole-branch review against the spec and this plan's Review Focus; one fix pass.
2. Push `release/v0.1.0` and open the pull request, with the previewed notes in its description. CI green.
3. Merge after pull request #18 has merged (it waits for the maintainer's hand checks).
4. On `main`: `airsign/scripts/release-check.sh 0.1.0 --notes <file>` passes.
5. With the maintainer's OK at that moment: push the tag and create the GitHub Release. Then suggest a description and topics for the repository, which are the maintainer's to set.
