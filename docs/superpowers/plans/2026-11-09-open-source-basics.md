# Open-Source Basics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the public AirSign repository a usable open-source project: MIT license, private vulnerability reporting, contributor docs, pseudonymous testers, hackathon material archived, clean repository hygiene. No app behaviour changes.

**Architecture:** Documentation and repository-layout work on branch `chore/open-source-basics`. Every task ends with a check command that failed (or found matches) before the task and passes after it, then a commit. The last task opens one PR, collects the two other contributors' agreement to MIT, applies GitHub settings and merges.

**Tech Stack:** Markdown, GitHub issue forms (YAML), git, Swift Package Manager (`swift test` as a regression check), Python 3 + numpy (tools/tuning unit tests).

**Spec:** `docs/superpowers/specs/2026-11-09-open-source-basics-design.md`

## Global Constraints

- New and edited project documents are in English. Archived Chinese documents keep their language.
- No real tester names in any tracked file. The names to scan for are in `.local/pseudonym-names.txt`; the replacements are in `.local/pseudonyms.tsv` (columns: name, English code, short code). Never commit either file, and never write a real name into a commit message, PR text or this plan.
- English text uses `Tester A`, `Tester B`, `Tester C`; Chinese text and data labels (test fixtures, `synth.py`) use `A`, `B`, `C`.
- Do not change: the `.airsign` magic `AIRSIGN1`, the HPKE info string `airsign-file-v1`, the HKDF salt in `RecoveryCode.swift`, the Keychain service `com.makeuc.airsign`, the bundle id `com.makeuc.airsign`, or any app behaviour. Code edits are limited to comments and test-fixture strings.
- Never open or print `.local/recovery-code.txt`.
- Commit messages: conventional prefixes (`docs:`, `chore:`, `test:`), no attribution lines.
- Pushing, opening the PR, posting on GitHub, changing repository settings and merging each need the maintainer's OK at that moment.
- License text: the standard MIT text, with `Copyright (c) 2026 The AirSign contributors`.
- Code of conduct: Contributor Covenant 2.1, enforcement contact `smallfire123123@gmail.com` (confirm with the maintainer before committing).

## Review Focus

1. Links break after files move (relative paths, `../` depth, `src=`/`href=` in HTML blocks): every relative link in every tracked `.md` must resolve. Pinned by the link check in Task 1 and re-run in Task 5.
2. A name survives in a form the replacement missed (possessive, a table cell, a code string, Chinese text): the whole-word, case-insensitive scan in Task 2 must print nothing.
3. GitHub does not detect the license because the MIT text was edited: after merge, `gh api repos/eric20041027/AirSign/license --jq .license.spdx_id` must print `MIT` (Task 5).
4. An issue form with invalid YAML is silently ignored by GitHub: every file in `.github/ISSUE_TEMPLATE/` must parse (Task 4).
5. A new `.gitignore` pattern hides a tracked file: `git ls-files -ci --exclude-standard` must print nothing (Task 4).

---

### Task 0: Branch and baseline

**Files:** none changed. Commit the spec and this plan.

- [ ] **Step 1:** `git switch -c chore/open-source-basics` from an up-to-date `main` (`git pull --ff-only` first).
- [ ] **Step 2:** Baseline: `cd airsign && swift test 2>&1 | tail -3`. Expected: `62 tests` passed (61 on a clone without the gitignored spike sessions).
- [ ] **Step 3:** Python baseline: `python3 -m venv "$TMPDIR/airsign-venv" && "$TMPDIR/airsign-venv/bin/pip" install -q numpy pyyaml && (cd tools/tuning && "$TMPDIR/airsign-venv/bin/python" -m unittest -q)`. Expected: `OK`.
- [ ] **Step 4:** Commit: `git add docs/superpowers/specs/2026-11-09-open-source-basics-design.md docs/superpowers/plans/2026-11-09-open-source-basics.md && git commit -m "docs: spec and plan for open-source basics"`.

### Task 1: Archive the hackathon material

**Files:**
- Move with `git mv` into `archive/makeuc-2026/` (same file names): `TEAM.md`, `docs/devpost.md`, `docs/demo-script.md`, `docs/algorithm-bakeoff.md`, `docs/algorithm-comparison.md`, `docs/evaluation.md`, `docs/technical-guide-zh.md`, `docs/test-protocol.md`, `docs/test-sessions.md`, `docs/tuning.md`.
- Move into `archive/makeuc-2026/superpowers/`: `docs/superpowers/specs/2026-11-07-airsign-design.md` → `superpowers/specs/`, `docs/superpowers/plans/2026-11-07-airsign.md` → `superpowers/plans/`.
- Create: `archive/makeuc-2026/README.md`.
- Modify: `README.md` (line 26 link, line 86 links, the Repository table), `archive/makeuc-2026/TEAM.md` (lines 6-7 links), `archive/makeuc-2026/devpost.md` (line 3 link depth), `archive/makeuc-2026/test-protocol.md:41` (link depth), `airsign/Sources/AirSignCore/Matcher.swift:5-9` (comments only), `tools/tuning/{README.md,tune.py,evaluate.py,bakeoff.py,algorithms_ref.py,quick_candidates.py,svgchart.py}`, `tools/session_analysis.py:3`, `tools/testlog_summary.py:17`, `spikes/airpods-motion/README.md` (first lines), `archive/makeuc-2026/superpowers/plans/2026-11-07-airsign.md:98`.

**Interfaces:** Produces the path `archive/makeuc-2026/` that Tasks 2, 3 and 5 use.

- [ ] **Step 1: Save the link check** as `$TMPDIR/check_links.py` (not committed):

```python
import re, subprocess, sys, pathlib
root = pathlib.Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
bad = []
for f in subprocess.check_output(["git", "ls-files", "*.md"], text=True, cwd=root).split():
    text = (root / f).read_text(encoding="utf-8")
    for target in re.findall(r'\]\(([^)\s]+)\)|(?:src|href)="([^"]+)"', text):
        t = next(x for x in target if x)
        if re.match(r"(https?:|mailto:|#)", t):
            continue
        path = (root / f).parent / t.split("#")[0]
        if not path.exists():
            bad.append(f"{f}: {t}")
print("\n".join(bad) or "all links resolve")
sys.exit(1 if bad else 0)
```

Run it now: Expected `all links resolve` (baseline).
- [ ] **Step 2:** Do the `git mv` moves listed above. Run the link check. Expected: FAIL, listing README.md, TEAM.md, devpost.md and test-protocol.md links.
- [ ] **Step 3:** Fix every link it lists: README → `archive/makeuc-2026/...`; TEAM.md → `superpowers/specs/...` and `superpowers/plans/...`; devpost.md → `../../README.md#what-we-measured`; test-protocol.md → `../../tools/session_analysis.py`. In the README Repository table, the `docs/` row becomes "Brand files, images and development plans" and a new row `archive/makeuc-2026/` reads "Hackathon records: test protocol and sessions, tuning, Devpost text, demo script, team plan (some in Chinese)".
- [ ] **Step 4:** Write `archive/makeuc-2026/README.md`: one paragraph saying these are the MakeUC 2026 (2026-11-07/08) working documents kept as a record and not maintained; a table of every file with one line each; a note that `evaluation.md` and `algorithm-comparison.md` are unfinished placeholders, and that `technical-guide-zh.md` describes the app as of the hackathon.
- [ ] **Step 5:** Repoint path mentions outside links: in `tools/` replace `docs/test-protocol.md`, `docs/algorithm-bakeoff.md`, `docs/evaluation.md`, `docs/algorithm-comparison.md`, `docs/tuning.md` with their `archive/makeuc-2026/` paths, and `C:/airsign-data` with `/path/to/airsign-data`. In `Matcher.swift:5-9` repoint the paths and replace the stale "Tonight's test-lab data ... decides the final value" with "The test-lab sessions (archive/makeuc-2026/test-sessions.md) kept 1.25." In the archived 2026-11-07 plan, replace the absolute home-directory path on line 98 with `MakeUC`. Prepend to `spikes/airpods-motion/README.md`: `> Hackathon prototype from MakeUC 2026, kept for reference and not maintained. The app lives in [airsign/](../../airsign/).`
- [ ] **Step 6: Verify.** `python3 "$TMPDIR/check_links.py"` → `all links resolve`. `git grep -n -E 'C:/airsign-data|/Users/' -- ':!docs/superpowers'` → no output (this spec and plan quote those strings). `git grep -n -E 'docs/(test-protocol|test-sessions|tuning|evaluation|algorithm-|devpost|demo-script|technical-guide)' -- ':!archive' ':!docs/superpowers'` → no output. `cd airsign && swift build` → succeeds.
- [ ] **Step 7: Commit:** `git add -A archive docs README.md TEAM.md tools spikes airsign/Sources/AirSignCore/Matcher.swift && git commit -m "docs: move MakeUC 2026 material to archive/makeuc-2026"`.

### Task 2: Pseudonymize the testers

**Files:** every tracked file the scan lists. Known today: `README.md:103,106`, `archive/makeuc-2026/{test-sessions.md,test-protocol.md,TEAM.md,algorithm-bakeoff.md,demo-script.md,technical-guide-zh.md}`, `airsign/Tests/AirSignCoreTests/AttemptLogTests.swift:11,19,20,46,56`, `tools/tuning/synth.py:78,87,88`, `tools/tuning/test_matcher.py:166`.

- [ ] **Step 1: Scan (RED).** `git grep -n -i -w -f .local/pseudonym-names.txt` → lists the files above.
- [ ] **Step 2:** Replace in English files with the English code (`Tester A`, possessive `Tester A's`), in Chinese files and in data labels with the short code (`A`). In `AttemptLogTests.swift` change both the labels and the expectations, so the tests still compare equal strings. In `test_matcher.py:166` the expected dict keys follow `synth.py` (`{"A": 1, "B": 1}`). In the archived TEAM.md, a role-table cell such as "name + Claude Code" becomes "隊友 A + Claude Code", matching the file's existing "隊友 C".
- [ ] **Step 3: Scan (GREEN).** Same command → no output.
- [ ] **Step 4: Regression.** `cd airsign && swift test 2>&1 | tail -3` → 62 passed. `(cd tools/tuning && "$TMPDIR/airsign-venv/bin/python" -m unittest -q)` → `OK`.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "docs: refer to testers by code name"` (check `git status` first: only the files from the scan).

### Task 3: License, credits and prior work

**Files:** Create `LICENSE`. Modify `README.md`, `CREDITS.md`.

- [ ] **Step 1: Check (RED).** `test -f LICENSE` → exit 1.
- [ ] **Step 2:** Create `LICENSE` with the standard MIT text from https://opensource.org/license/mit, unedited except the copyright line `Copyright (c) 2026 The AirSign contributors`.
- [ ] **Step 3:** README: add a badge `<img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-111214">` after the existing badges; add `## License` at the end: "MIT, see [LICENSE](LICENSE). Brand files are included; see [CREDITS.md](CREDITS.md) for the fonts." In `## Team`, add one sentence: Shao, Yang, Wang and Ma published a different system also called "AirSign" (smartphone signatures in the air, *Sensors* 21(1):104, 2020, doi:10.3390/s21010104); this project is unrelated.
- [ ] **Step 4:** CREDITS.md: add `## Trademarks` — "AirPods, Mac, macOS and Finder are trademarks of Apple Inc. AirSign is not affiliated with or endorsed by Apple."
- [ ] **Step 5: Verify.** `head -1 LICENSE` → `MIT License`; `grep -c 'The AirSign contributors' LICENSE` → `1`; link check → `all links resolve`.
- [ ] **Step 6: Commit:** `git add LICENSE README.md CREDITS.md && git commit -m "docs: MIT license, trademark note, prior work with the same name"`.

### Task 4: Security policy, contributor docs, templates, .gitignore

**Files:** Create `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/ISSUE_TEMPLATE/config.yml`, `.github/PULL_REQUEST_TEMPLATE.md`. Modify `.gitignore`, `README.md`.

- [ ] **Step 1: Check (RED).** `git check-ignore -q reports/x research_notes/x airsign/.swiftpm/x .venv/x tools/__pycache__/x` → exit 1. `ls SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md .github` → errors.
- [ ] **Step 2:** `.gitignore`: add `reports/`, `research_notes/`, `.swiftpm/`, `xcuserdata/`, `__pycache__/`, `.venv/`.
- [ ] **Step 3: `SECURITY.md`.** Supported: the `main` branch (no releases yet). Report privately through the repository's Security tab → "Report a vulnerability" (GitHub private vulnerability reporting); never in a public issue. Best-effort student project: we aim to reply within 7 days. In scope: the `.airsign` format and crypto, key and recovery-code handling, the Keychain items, lockout, accepting a signature or AirPods that should be rejected, plaintext left on disk beyond what the README documents. Known limitations, not vulnerabilities: copy the README "Security model" rows marked ❌ and ⚠️ with a link to that section.
- [ ] **Step 4: `CONTRIBUTING.md`.** Requirements (Apple-silicon Mac, macOS 14+, Xcode 16+; AirPods with head tracking only to run the app, not for `swift test`); build and test (`cd airsign && swift test`, `scripts/install.sh`, `AIRSIGN_ADHOC=1 scripts/install.sh` without an Apple Development certificate, with the Keychain-prompt caveat from `build-app.sh`); layout (`AirSignCore` is pure logic with Swift Testing tests, `AirSign` is the SwiftUI app, `tools/tuning` is the Python port with `python -m unittest` and numpy); rules: tests first for any Core change; one topic per PR; conventional commit prefixes; update README when behaviour changes; never commit signature recordings, test logs or recovery codes; never change the identifiers listed in Global Constraints without a migration; set a GitHub noreply commit email; security issues go to SECURITY.md.
- [ ] **Step 5: `CODE_OF_CONDUCT.md`.** Contributor Covenant 2.1 verbatim from https://www.contributor-covenant.org/version/2/1/code_of_conduct/, with `[INSERT CONTACT METHOD]` replaced by `smallfire123123@gmail.com`.
- [ ] **Step 6: Templates.** `bug_report.yml` (issue form: name, description, labels `[bug]`; textareas "What happened", "Steps to reproduce"; inputs "macOS version", "Mac model and chip", "AirPods model", "AirSign commit or build"; a markdown block: "Don't paste your recovery code, `profile.bin` or test-lab logs: they hold secrets or your signature's motion."). `feature_request.yml` (problem, proposed solution, alternatives). `config.yml`: `blank_issues_enabled: false` and a contact link "Report a security vulnerability" → `https://github.com/eric20041027/AirSign/security/advisories/new`. `PULL_REQUEST_TEMPLATE.md`: summary; checklist — `swift test` passes, README updated if behaviour changed, no recordings/logs/recovery codes, no identifier changes.
- [ ] **Step 7: README.** In `## Install`, after the build commands: no Apple Development certificate → `AIRSIGN_ADHOC=1 scripts/install.sh` (macOS may then ask for your password after each rebuild). New `## Uninstall` after Quick start: delete `~/Applications/AirSign.app` and `~/Library/Application Support/AirSign`, delete the Keychain items of service `com.makeuc.airsign` (accounts `profile-key`, `master-key`, `paired-recovery-keys`, `lockout`, and `selftest` if present) with `security delete-generic-password -s com.makeuc.airsign -a <account>`, run `/System/Library/CoreServices/pbs -update`; warn first that without the master key existing `.airsign` files open only with the recovery code. New `## Contributing` before `## Team`: one paragraph linking CONTRIBUTING.md, SECURITY.md and CODE_OF_CONDUCT.md.
- [ ] **Step 8: Verify.** `git check-ignore -q reports/x research_notes/x airsign/.swiftpm/x .venv/x tools/__pycache__/x` → exit 0. `git ls-files -ci --exclude-standard` → no output. `for f in .github/ISSUE_TEMPLATE/*.yml; do "$TMPDIR/airsign-venv/bin/python" -c "import sys,yaml; yaml.safe_load(open(sys.argv[1]))" "$f" || echo "BAD $f"; done` → no `BAD`. `grep -c 'INSERT CONTACT' CODE_OF_CONDUCT.md` → `0`. Link check → `all links resolve`. Name scan from Task 2 → no output.
- [ ] **Step 9: Commit:** `git add .gitignore SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md .github README.md && git commit -m "docs: security policy, contributing guide, code of conduct, issue and PR templates"`.

### Task 5: Publish, agreement, settings, merge

Each step below needs the maintainer's OK when it is reached.

- [ ] **Step 1: Final checks.** Link check, name scan, `swift test` (62 passed), Python unittest (`OK`), `git status` clean except untracked local folders.
- [ ] **Step 2:** `git push -u origin chore/open-source-basics`, then `gh pr create` with title `docs: open-source basics (MIT license, security policy, contributor docs, archive)` and a body listing the five tasks, a test plan, and a closing request: "Both other contributors: please comment 'I agree to license my contributions to AirSign under the MIT License.'" (the maintainer adds the two @-mentions himself).
- [ ] **Step 3:** Wait for both agreement comments on the PR. Do not merge without them.
- [ ] **Step 4: Repository settings.** `gh api -X PUT repos/eric20041027/AirSign/private-vulnerability-reporting` (expect HTTP 204); `gh repo edit eric20041027/AirSign --description "Lock Mac files by signing in the air with an AirPod" --add-topic macos --add-topic swift --add-topic airpods --add-topic encryption --add-topic biometrics --add-topic cryptokit --enable-wiki=false`. Verify: `gh api repos/eric20041027/AirSign/private-vulnerability-reporting --jq .enabled` → `true`.
- [ ] **Step 5:** `gh pr merge --merge`, `git switch main && git pull --ff-only`.
- [ ] **Step 6: Verify on GitHub.** `gh api repos/eric20041027/AirSign/license --jq .license.spdx_id` → `MIT`. `gh api repos/eric20041027/AirSign/community/profile --jq .health_percentage` → higher than 14. The new-issue page shows the two forms and the security link.
