# First release: design

Sub-project D of four (A open-source basics, B security fixes, C architecture and CI, D release). Date: 2026-11-13.

## Intent

The repository has only ever had `main`. Someone who wants to use AirSign has no version to name, no list of what changed since the hackathon build, and no statement of which code the security policy covers. This sub-project makes the first release, `0.1.0`, from source: a tag, a changelog, release notes and install steps that point at the tag. It also writes down how a release is made, so the next one does not depend on anyone's memory.

It adds no feature and ships no downloadable app.

## Goals

"Now" is `main` at de4d58c, plus pull request #18 (the rules move into the core library; file work runs in the background), which merges before the release is cut.

### 1. The version has one name everywhere

**Now.** `Info.plist` says version `0.1`, build `1`. Nothing else names a version. There is no tag.

**After.**

- The first release is `0.1.0`. `CFBundleShortVersionString` is `0.1.0`; `CFBundleVersion` stays `1`. The app's About panel shows it, as macOS does for any app; no new code.
- The tag is `v0.1.0`, annotated, on the commit of `main` that the release notes describe and that CI passed.
- Versions follow semantic versioning from here on. While the version is below 1.0 the `.airsign` format and the Keychain items still do not change without a migration: that promise is in CONTRIBUTING.md already and the release does not weaken it.

### 2. A changelog

**Now.** What changed is spread over four pull requests and three design documents.

**After.**

- `CHANGELOG.md` at the repository root, in the "Keep a Changelog" layout: newest release first, an `Unreleased` section at the top, each release with its date and the headings it needs out of Added, Changed, Fixed, Security.
- The `0.1.0` entry says, in plain words a user can follow:
  - what AirSign is and does in this release (a short paragraph, not the README again);
  - what changed since the state reviewed on 9 November 2026 (commit 5ca039a, before the security fixes), grouped, taken from pull requests #16, #17 and #18 and checked against the code: the security fixes (a restored file or folder appears whole or not at all, with the exception SECURITY.md gives for drives that cannot rename without replacing; an unreadable profile or key never costs the master key; changing the clock no longer ends a cooldown while the Mac has not restarted; research and debug features are only in lab builds; pairing is in the security model); saving the profile can't half-succeed; "Forget paired Macs" works when the pairing keys can't be read; file work runs in the background, one operation at a time;
  - what someone upgrading from an older build must know: the one-time 4-hour cooldown when the Keychain has no lockout item, and how to check;
  - where the known limits are (a link to SECURITY.md; they are not repeated).
- Every statement in it is true of the code at the tag. It promises nothing SECURITY.md does not.

### 3. The release on GitHub

**After.**

- A GitHub Release named `AirSign 0.1.0` for the tag `v0.1.0`, with notes made of: the `0.1.0` section of the changelog; what is needed (Apple silicon, macOS 14 or later, AirPods with head tracking, Xcode 16 or later); how to install from the tag (the same commands as the README); and one plain paragraph on why there is no app to download: a download that opens with a double-click needs an Apple Developer ID certificate and notarization, which this project does not have, so AirSign is built from source and signed on the user's own Mac.
- Nothing is attached. GitHub adds the source archives itself.
- It is marked as the latest release, not as a pre-release.

### 4. The documents point at the release

**After.**

- README: a badge showing the latest release, next to the CI badge. The Install section clones the tag (`git clone --branch v0.1.0 --depth 1 …`) and says in one sentence that there is no prebuilt app and why. The line for building the newest code from `main` stays, as the second option.
- SECURITY.md, "Supported versions": the latest release and `main` get security fixes; older releases do not.
- CONTRIBUTING.md: a line pointing at `docs/RELEASING.md`, and "add a line under Unreleased in CHANGELOG.md when a change is one a user would notice" among the rules for changes. The PR template gains that item.

### 5. Making a release is written down and checked

**After.**

- `docs/RELEASING.md`: the steps, in order, with the exact commands: choose the version; move the `Unreleased` entries into a dated section; set the version in `Info.plist`; open a pull request; after it merges, run the release check; tag; push the tag; create the GitHub Release from the notes file; then the two things to look at afterwards (the release page, the badge). It says who may publish: a maintainer, on their own decision.
- `airsign/scripts/release-check.sh <version>` is run before tagging. It changes no tracked file and publishes nothing; what it writes is what `check.sh` writes (build products and a temporary disk image) and, when asked, the notes file. It fails, saying why, unless all of these hold: `Info.plist` has that version; `CHANGELOG.md` has a section for that version with a date, and the `Unreleased` section is empty (everything in it has moved into the release being cut); the working tree is clean and is `main` at the same commit as `origin/main`; the tag `v<version>` does not exist locally or on the remote; CI passed on that commit; `airsign/scripts/check.sh --with-test-volume` passes. With `--notes <file>` it also writes the release notes (goal 3) to that file. It needs the network and the `gh` command, and says so when either is missing.
- The pull-request check (`check.sh`) does not change. Its six checks stay six.

## Order of work

1. One pull request, `release/v0.1.0`: goals 1, 2, 4 and 5, and the notes text of goal 3 as the script will write it. CI passes on it.
2. Pull request #18 merges first (it needs the maintainer's hand checks), then this one.
3. On `main` after both: `release-check.sh 0.1.0 --notes …` passes. Then, with the maintainer's OK at that moment: the tag is pushed and the GitHub Release is created.

## Non-goals

- No downloadable app, no signing identity beyond what a user has, no notarization, no disk image, no Homebrew formula, no auto-update.
- No release workflow in CI: there is nothing to build and attach, and publishing is a person's decision.
- No change to the app's behaviour, wording or screens; no version shown in a new place.
- No change to the `.airsign` format, the Keychain items, the bundle id, or `check.sh`.
- No signed tag: the project has no published signing key. (An annotated tag is used.)
- No change to the repository's description or topics on GitHub: a repository setting, left to the maintainer.

## Anti-goals

- A tag on a commit that CI did not pass, or that is not what the notes describe.
- Release notes or a changelog that promise more than SECURITY.md, or that describe pull request #18's changes while it is not merged.
- A tag or a release published without the maintainer's OK at that moment.
- A release check that can pass on a dirty tree, on a branch other than `main`, or without running the tests.
- Real tester names, machine paths, or anything from `.local/` in any released text.

## Constraints

- English for all new text; plain words, short sentences, like the documents already there. Commit prefixes `docs:`, `chore:`, `ci:`; no attribution lines.
- `airsign/scripts/check.sh` keeps passing. The README still has exactly one place where a number is followed by ` unit tests`.
- Never read anything under `.local/`. No test, check or script touches the real Keychain items or the real Application Support folder. Nobody launches the built app from a script.
- The date in the changelog is the day the release pull request is written. It is not corrected if the tag is pushed on a later day: a correction would change the commit that was checked. The tag and the GitHub Release carry their own dates.
- Pushing a branch and opening a pull request are the builder's; merging follows CI and review as for the other sub-projects; pushing the tag and creating the GitHub Release need the maintainer's OK at that moment.

## Decisions taken by the maintainer

| Question | Decision |
|---|---|
| What is released | Source only (decided 2026-11-13). The Mac has an Apple Development certificate and no Developer ID, and the maintainer chose not to add a paid developer account for this release |
| CI before merging | The `check` status is required on `main` (set 2026-11-13) |
| Questions | Skipped: the maintainer asked for the remaining choices to be made by the designer, with notice of major ones |

## Calls made by the designer (for the maintainer to check)

| Question | Call | Why |
|---|---|---|
| Version number | `0.1.0` | `Info.plist` already says 0.1; the evaluation behind the matcher is small (README says so), and 1.0 would claim more than that |
| Tag | `v0.1.0`, annotated, unsigned | The usual form; a signed tag needs a published key the project does not have |
| Changelog layout | Keep a Changelog, with an Unreleased section | Widely known, readable without tooling, and it gives contributors one place to add a line |
| Release notes | Generated from the changelog section by the release check, plus fixed install text | One source for what changed; no second text to keep true |
| Date in the changelog | The day the release pull request is written, never corrected afterwards | Correcting it after the merge would change the commit that CI and the release check passed |
| `Unreleased` at release time | Must be empty | The script can check that; it cannot tell which leftover entries belong to which release |
| Release workflow in CI | None | Nothing to build; publishing stays a person's step |
| How the release is checked | A separate `release-check.sh`, read-only | Keeps `check.sh` at its six checks; the things a release needs (clean `main`, matching version, tag free, CI passed) are not things a pull request should fail on |
| Install text | Clone the tag, shallow | A user gets exactly the released code; `main` stays documented as the second option |
| Supported versions | The latest release and `main` | A small team; promising fixes for older releases would be a promise nobody can keep |
| Signed commits or tags | No | Not used anywhere in the project so far |
| GitHub description and topics | Not touched | A repository setting; suggested to the maintainer after the release |

## Left to the builder

The wording of the changelog, the notes and RELEASING.md within the facts above; how the script reads the version from `Info.plist` and the section from the changelog, and how it learns that CI passed on the commit; the badge's exact form; the name of the notes file.
