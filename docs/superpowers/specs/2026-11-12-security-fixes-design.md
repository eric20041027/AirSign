# Security fixes: design

Sub-project B of four (A open-source basics, B security fixes, C architecture and CI, D release). Date: 2026-11-12.

## Intent

The 2026-11-09 review found six real weaknesses in the app. None breaks the encryption, but each one either leaves plaintext behind, lets the owner destroy their own key by following the app's advice, gives an attacker more tries or more information than the design promises, or is missing from the documented security model. This sub-project fixes them before the first release (sub-project D), so the release does not ship known weaknesses.

## Goals

Each goal is one of the six findings. "Now" is the behaviour on `main` at 5ca039a.

### 1. Less plaintext left on disk

**Now.** Restoring a file writes the plaintext straight to its final name, so a crash or a full disk can leave a partial plaintext file that looks like the real one. Locking or unlocking a folder puts its zip (and, when unlocking, the unpacked folder) in a scratch folder that is removed only when the function returns: `airsign-<UUID>` in the system temporary folder, or a folder macOS picks for item replacement. Nothing removes a scratch folder that a crash left behind.

**After.**

- **Restoring is all-or-nothing.** The plaintext of a file or a folder is first written under a hidden name next to the locked file, `.airsign-partial-<UUID>`, and moved to its final name only when complete. A failed restore removes the partial. An existing file is still never overwritten. The item-replacement folder is no longer used.
- **Leftovers are removed.** Scratch folders in the system temporary folder are named `airsign-scratch-<UUID>` and created 0700. When AirSign starts it removes leftover scratch folders from the system temporary folder, and when it unlocks a file it first removes leftover partials from that file's folder. A leftover is removed only when AirSign made it and nothing is using it: the name is exactly the prefix plus a UUID, it is a folder holding AirSign's marker file, and the lock AirSign holds on that marker while it works is free. Anything else with such a name is left alone.
- **What stays, documented in README and SECURITY.md:** locking moves the original to the Trash; if AirSign is killed in the middle of a restore, a hidden partial can remain next to the locked file until AirSign next unlocks something in that folder. On a volume with no exclusive rename (exFAT, FAT) a folder is still published whole, but a single file is written straight to its final name with an exclusive create: nothing is overwritten, and a kill at that moment can leave an incomplete file under that name while the locked file stays.

### 2. An unreadable profile or key never costs the master key

**Now.** When `profile.bin` exists but can't be read (for example the Keychain prompt was denied), the app says "Enroll again" and shows the enroll screen; enrolling creates a new master key over the old one, and every file locked before then opens only with the recovery code. Reading a key that is missing from the Keychain silently creates a new one: for the master key, locking then "works" with a key no existing file uses; for the profile key, an unreadable profile gains a useless new key.

**After.**

- The app tells apart three states at launch: **no profile** (no `profile.bin`: first run, enroll), **ready**, and **blocked** (`profile.bin` exists but the profile, its key or the master key is missing or can't be read).
- **Blocked** shows a blocking screen, never the enroll screen: what is wrong in plain words, **Try again**, **Unlock with the recovery code…** (a file picker; opening `.airsign` files from Finder works too), **Reset AirSign…** and **Quit**. Locking is refused while blocked. The same screen appears if a key turns out to be missing later, when locking or unlocking.
- Reading a key never creates it. A new master key and profile key are created only when a first enrollment or a reset is saved.
- **Reset AirSign…** asks for confirmation in plain words (files locked so far will open only with their recovery code; paired Macs are forgotten), then starts a normal enrollment. Nothing is removed at that point. The old profile and keys are replaced only when the new enrollment is saved, which already waits until the new recovery code is confirmed; cancelling or quitting before then returns to the blocking screen with everything intact. Replacing deletes the old Keychain items and adds new ones, so an old item that can't be read can't stop the reset.
- Saving a first enrollment refuses to replace an existing `profile.bin` unless it comes from Reset. With no `profile.bin` the existing rule stays: enrolling makes a fresh master key, so a new signer can never open files locked earlier.

### 3. The lockout is harder to end early

**Now.** The cooldown ends when the wall clock passes a stored date, so setting the Mac's clock forward ends it at once. The count is kept in `profile.bin` and in a Keychain item; the stricter one wins, so restoring an old `profile.bin` alone does not reset it, but deleting the Keychain item and then restoring an old `profile.bin` does. Deleting a login-Keychain item needs no password.

**After.**

- A lockout records the boot session and the continuous uptime (which keeps counting during sleep) when it starts. **While the Mac has not restarted, uptime alone decides** when the cooldown ends; changing the clock in either direction has no effect. **After a restart the wall clock decides the initial time left**, capped at the cooldown's own length. AirSign saves that time against the new boot, so uptime counts it down from then on. Saved lockouts without the new fields still load; the wall clock supplies their initial time left.
- **A missing Keychain copy fails closed.** If `profile.bin` exists and the Keychain has no lockout item, AirSign treats that as tampering: it starts the longest cooldown (4 hours) and saves it. Every save writes that item, so it is only ever missing when something removed it.
- **What stays, documented.** Someone who can use the Mac as the owner can copy and later restore everything AirSign stores (its folder and the Keychain file) and so roll the count back; a restart followed by a clock change also ends a cooldown. No local-only fix closes these. The README's row for "uses your unlocked Mac" and SECURITY.md say so: the lockout slows such a person, it does not stop a determined one.

### 4 and 5. Research and debug features are not in the app people install

**Now.** `--test-mode` (the test lab: after one accepted signature, unlimited uncounted attempts that show scores, and raw signature motion written to plaintext logs), `--probe` and `--selftest-keychain` work in every build. The self-test leaves a Keychain item behind. With no profile, `demoMode` reads as on.

**After.**

- The app's test lab, probe and Keychain self-test are compiled only into a **lab build**: `AIRSIGN_LAB=1 scripts/build-app.sh`, or a debug build (`swift build`, `swift run`). The default `scripts/build-app.sh` output ignores all three flags. Check: `strings` on the default binary finds none of the three flag names; on a lab build it finds all three.
- `AttemptLog` stays in `AirSignCore` as a tested library type; only the app's use of it is conditional. Moving it is sub-project C's business.
- A lab build says so: the window title is "AirSign (lab build)".
- `--selftest-keychain-clean` (lab build) deletes the self-test item; the uninstall steps keep covering it.
- With no profile, demo mode is off.
- CONTRIBUTING.md explains the lab build: it shows scores, writes signature motion in plaintext to the logs folder, and is for evaluation only.

### 6. Pairing is in the security model

**Now.** Pairing a second Mac stores the first Mac's recovery private key in the second Mac's Keychain, and the README does not say so.

**After.** README and SECURITY.md say: what pairing stores and where; that a paired Mac can open the files the other Mac locked under the recovery code used to pair, after its own signature check, and that a reset or a fresh enrollment on the other Mac needs a new pairing; that anyone who can read the paired Mac's Keychain gets the equivalent of the other Mac's recovery code; and how to unpair ("Forget paired Macs"). Changing a signature keeps its recovery code; keep old codes for files locked before a reset or fresh enrollment. README also gains a short "Pairing a second Mac" how-to, because the feature is otherwise undocumented. No change to how pairing works.

## Non-goals

- No change to the `.airsign` format, the HPKE info string, the HKDF salt, the Keychain service name or account names, the bundle id, or the profile's encryption.
- No redesign of pairing (for example a per-pair key instead of the recovery key).
- No Secure Enclave or Keychain access-control changes (README roadmap).
- No moving of file IO off the main thread and no splitting of `AppModel.swift`: sub-project C. B adds only the small core types its fixes need, with tests.
- No removal of the test lab itself; it stays as the evaluation tool in lab builds.
- No CI, versioning or signed release (C and D).

## Anti-goals

- A fix that can lose a user's file or key in a new way. Every change to lock, unlock, enroll and reset keeps "the original is removed only after the copy is verified" and "nothing is overwritten".
- A sweep that deletes anything AirSign did not create.
- A default build in which any of the three flags does anything.
- A profile written by this branch that the app at 5ca039a can't read, or the reverse.

## Constraints

- TDD: every behaviour change in `AirSignCore` gets a test that fails first. Key creation and lockout timing are already in `AirSignCore`; the unreadable-profile handling now in `AppModel` (the launch state and what each state allows) moves into `AirSignCore` far enough to be tested without the UI.
- `swift build` stays at 0 warnings. The existing 62 tests keep passing, except the two in `LockoutAndProfileTests.swift` that rely on `masterKey()` creating a key: they are rewritten for the new rule.
- English for all new text. Commit prefixes `fix:`, `test:`, `docs:`; no attribution lines.
- Never open or print `.local/recovery-code.txt`. No real tester names in tracked files. No test or check touches the real Keychain items under `com.makeuc.airsign` or the real `~/Library/Application Support/AirSign`.
- Pushing, opening the PR and merging each need the maintainer's OK at that moment.
- The maintainer checks by hand on their Mac, before merge: lock and unlock a file and a folder, a wrong signature, the lockout message, and that `--test-mode` does nothing in the default build.

## Decisions taken by the maintainer

| Question | Decision |
|---|---|
| Scope | All six findings |
| Order | B, then C, then D, each with its own spec, plan and PR |
| Pairing (finding 6) | Document only; no redesign, no format change |

## Calls made by the designer (for the maintainer to check)

| Question | Call | Why |
|---|---|---|
| Lockout rollback | Fail closed on a missing Keychain copy, and say plainly in README and SECURITY.md that the lockout can be rolled back by someone using the Mac as the owner | Deleting one Keychain item is too easy to leave open; a full rollback can't be stopped locally, so the documents must not promise more |
| Lockout clock | Uptime decides within a boot; wall clock after a restart, capped at the cooldown's length | Closes the easy bypass with no new storage |
| Test lab, probe, self-test | Compile out of the default build; opt in with `AIRSIGN_LAB=1` or a debug build | Removes the score oracle and plaintext motion logs from what people install, keeps the evaluation tool for contributors |
| Blocked state | One blocking screen for an unreadable profile and a missing key: Try again, Unlock with the recovery code, Reset, Quit | The owner must never lose the master key by following the app's own advice |
| Reset | Removes nothing until the new enrollment is saved | Quitting half-way must not cost the key |
| Restore leftovers | Hidden partial next to the locked file, removed at the next unlock in that folder; strict-name sweep of the temporary folder at launch | No new stored state, nothing swept that AirSign did not create |
| `AttemptLog` in the core library | Stays | Not reachable from the default app; moving it is C |
| Dead code in the review (`isDirectory`, `stop()`) | Left for sub-project C | Not a security fix |

## Left to the builder

The names of new types and errors; the exact wording of messages and documents within the facts above; the layout of the blocking screen (it follows the existing screens' style); how the lab build flag reaches the compiler.
