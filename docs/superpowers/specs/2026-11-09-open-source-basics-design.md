# Open-source basics: design

Sub-project A of four (A open-source basics, B security fixes, C architecture and CI, D release). Date: 2026-11-09.

## Intent

MakeUC 2026 is over. AirSign's repository is public but has no license, so legally nobody may use it. It also mixes hackathon material with the project and names the teammates who tested it. This sub-project makes the repository a real open-source project that a stranger can use, contribute to and report vulnerabilities in, without changing how the app behaves.

## Goals

1. A license: **MIT**, copyright "The AirSign contributors", agreed by all three contributors.
2. A way to report vulnerabilities privately: `SECURITY.md` plus GitHub private vulnerability reporting.
3. Contributor basics: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1, contact: the maintainer's personal email), issue and PR templates.
4. Testers are pseudonymous in every tracked file: **Tester A, Tester B, Tester C** in English text, **A, B, C** in Chinese text and in data labels. The name-to-code table lives only in `.local/pseudonyms.tsv` (gitignored) and is never committed.
5. Hackathon material moves to `archive/makeuc-2026/` with an index README; history is kept, nothing is deleted.
6. Repository hygiene: `.gitignore` covers local folders and tool caches; no machine paths (`C:/airsign-data`, a home directory) in tracked files; README covers the license, contributing, prior work with the same name, and how to uninstall.

## Non-goals

- No change to app behaviour, the `.airsign` format, the Keychain service name or the bundle id (sub-projects B and D).
- No CI, versioning, tags, CHANGELOG or signed release (C and D).
- No rewrite of git history; commit emails stay as they are. New commits should use a GitHub noreply address.
- No English translation of the Chinese hackathon documents; they are archived as written.

## Decisions taken by the maintainer

| Question | Decision |
|---|---|
| License | MIT |
| Named testers | Replace with code names; mapping kept locally |
| Hackathon material | Move to an archive folder, keep it public |
| Personal emails in history | Keep; no history rewrite |
| Code of conduct contact | The maintainer's personal email |

## Left to the builder

Wording of the new documents, within the facts in README and the review in `.local/oss-review-2026-11-09.md`; the exact layout of the archive index; the issue template fields.
