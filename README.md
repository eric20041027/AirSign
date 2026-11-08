# AirSign

**Lock any file on your Mac with a signature you draw in the air while holding one AirPod.**
Only your AirPods, your grip and your wrist rhythm open it again.

Built at MakeUC 2026 (Security track) by a team of three, starting 2026-11-07 12:00 ET.

## Why

- Passwords leak and get reused, and many people assume theirs already have.
- Not every Mac has a fingerprint reader (desktop Macs often don't), and some people refuse to put body biometrics on any computer.
- A fingerprint is a secret for life and is left on every cup you touch. An air signature can be changed if it ever leaks.
- AirPods belong to one person, while computers are often shared. Someone trying with their own AirPods is turned away before their signature is even scored.
- Everything stays on your Mac. AirSign makes no network connections.

Think of it as a second lock for personal files: even if someone uses your unlocked Mac, the files you locked stay locked.

## How it works

1. **Enroll.** Hold one AirPod in your signing hand with a finger over its in-ear sensor, keep the other one in the case, and sign in the air three times (about 2 seconds each), then three more times as a check: if any check doesn't match, the enrollment wasn't steady enough and you start over. A strength meter, like a password's, rates the signature on length, amount of wrist turning, changes of direction and how many axes it uses; a weak one (under 1.5 s, under 3 rad of turning, fewer than 8 changes of direction, or 85% on one axis) is refused before the checks, because short simple gestures are the easiest to copy. AirSign records which AirPods and which bud you used and shows a recovery code once. The preview draws your signature in 3-D; drag it to look from any angle.
2. **Lock.** In Finder, right-click a file → **Lock with AirSign**. It becomes `name.ext.airsign`. The original moves to the Trash only after the locked copy has been decrypted in memory and checked byte for byte.
3. **Unlock.** Right-click the `.airsign` file → **Unlock with AirSign**, press Space, sign, hold still.

**The checks, in order**

| Gate | What it checks | How it decides |
|---|---|---|
| 1. Your AirPods | The same AirPods (sound-output ID) and the same bud as at enrollment | Hard gate, checked before any scoring |
| 2. Grip and plane | How the AirPod is tilted through the signature (gravity direction) | One combined score |
| 3. Size and tempo | Acceleration and how long the signature takes | One combined score |
| 4. Wrist rhythm | Rotation rate from the gyroscope, the part nobody can see | One combined score |

Gates 2–4 feed a single dynamic-time-warping score compared against your three enrolled signatures. The threshold is 1.25 × the largest difference between your own enrolled signatures, so it adapts to how consistent you are. In demo mode the app also lights up which gate differed most.

**Encryption**

- Each file gets its own random 256-bit key and is sealed with AES-GCM. The header is authenticated together with the content, so editing or renaming it breaks decryption.
- That file key is wrapped twice:
  - with a master key kept in this Mac's login Keychain. Locking uses it without a signature, like zipping a file; unlocking uses it only after a signature passes;
  - with HPKE (X25519, ChaCha20-Poly1305) to a public key derived from your recovery code, so the code opens the file on any Mac.
- The header (original file name, time, wrapped keys) is readable. Only the content is ciphertext.

**Other protections**

- 5 failures in a row lock unlocking for 5 minutes, then 15 minutes, 1 hour and 4 hours until you get in. The count is also kept in the Keychain, so restoring an old profile file doesn't reset it.
- Changing the signature always needs the recovery code, so one lucky imitation can't take over.
- Scores and gate lights appear only in demo mode, which starts off and needs the owner to turn on.
- A fresh enrollment replaces the master key and forgets every paired Mac.

**Your other Macs.** Open a file once with its recovery code and tick "Remember on this Mac". From then on, your AirPods and signature on that Mac open files locked on the first one. Only Macs where you enrolled your own signature can be paired. On a public Mac, type the recovery code once and nothing is kept.

## Install

Requirements: macOS 14 or later; AirPods Pro, AirPods (3rd or 4th generation) or AirPods Max; Xcode with an Apple Development certificate (Xcode → Settings → Accounts → Manage Certificates → + → Apple Development).

```bash
git clone https://github.com/eric20041027/AirSign.git
cd AirSign/airsign
swift test                # 46 tests
scripts/install.sh        # builds, signs, installs to ~/Applications, registers the Finder items
```

If the Finder items don't appear, enable them in System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders.

## Threat model

| Attacker | Stopped? | Why |
|---|---|---|
| Copies or emails your `.airsign` file | Yes | The master key never leaves your Mac's Keychain |
| Uses your logged-in Mac while you're away | Partly | They must pass all gates, and the lockout keeps growing. How well this holds depends on the per-try imitation rate measured in [docs/evaluation.md](docs/evaluation.md) |
| Steals your AirPods | Yes | They still need your grip and rhythm |
| Tries with their own AirPods | Yes | Gate 1 turns them away before scoring. It's a deterrent check: the ID is the Bluetooth address, so it is never used as a key |
| Watched you sign and imitates | Partly | See the numbers below |
| Gets one lucky pass and tries to re-enroll | Yes | Changing the signature needs the recovery code |
| Knows your Mac login password and can read the Keychain | No | The signature guards the key; it is not the key. See the roadmap |
| Finds the original in the Trash | No | Empty the Trash after locking (see below) |
| Has your recovery code and the file | No | The code is a master key. Keep it offline |
| You lose your AirPods | You're not locked out | Use the recovery code, then enroll new AirPods |

## Results so far

Spike recordings from 2026-11-07, one owner, one right AirPod, imitators who watched the owner first ([docs/tuning.md](docs/tuning.md)):

| Round | Owner accepted | Imitators accepted | AUC |
|---|---|---|---|
| 1, imitators hadn't learned the grip | 25/28 | 0/9 | 0.99 |
| 2, imitators copied the grip | 10/10 | 1/14 | 0.96 |

The full multi-round evaluation in the test lab (two owners, three sessions, five attack scenarios, about 340 attempts) is in [docs/evaluation.md](docs/evaluation.md) once it's run; the protocol is [docs/test-protocol.md](docs/test-protocol.md).

## Deploying safely

AirSign protects files, not your login session. To get the protection the threat model describes:

1. **Turn on FileVault**, so the disk (and the Keychain file) is encrypted when the Mac is off.
2. **Empty the Trash after locking.** AirSign moves the original there instead of deleting it, so a bug can never lose your file.
3. **Mind your backups.** Time Machine, iCloud Drive or other sync tools may already hold a plaintext copy from before you locked it. Lock sensitive files before they are backed up, or remove older backups.
4. **Keep demo mode off** in daily use. It shows scores and gate lights.
5. **Keep the recovery code offline**, on paper or in a password manager you trust, never in a file on the same Mac.
6. **Pair only Macs where you have your own user account.** On a shared or public Mac, use the recovery code once instead.
7. **Lock your screen when you walk away.** AirSign keeps the locked files closed, but anything already open stays open.
8. **Before signing:** your AirPods must be the sound output, the other bud should be in its case, and an iPhone nearby shouldn't take over the AirPods.

## Limits

- macOS only, because only Apple exposes AirPods motion to apps.
- A skilled imitator can sometimes pass (1 in 14 in round 2). That's why AirSign is a second factor for personal files, not a vault.
- The signature guards the key rather than being the key.
- The `.airsign` header shows the original file name and time.

## Roadmap

- Derive the key from the signature itself (a fuzzy extractor), so there is no stored key to steal and files travel with you.
- An iPhone relay, so Windows and Linux laptops can use AirPods too.
- A duress signature that opens a decoy.
- Secure delete instead of the Trash.

## Repository

| Path | What's there |
|---|---|
| `airsign/` | The Swift package: `AirSignCore` (matcher, crypto, file locking, lockout; all tested) and the `AirSign` app |
| `docs/superpowers/specs/` | The design and threat model |
| `docs/superpowers/plans/` | The implementation plan we built from |
| `docs/test-protocol.md`, `docs/evaluation.md`, `docs/tuning.md` | How we tested and what we measured |
| `tools/tuning/` | Python port of the matcher for threshold tuning |
| `spikes/airpods-motion/` | The throwaway prototype that proved the AirPods signal first |

**How we built it.** We wrote a design and a task-by-task plan first, then built the core test-first. Claude Code and Antigravity were our coding assistants. Commit history starts at the beginning of the event.

## Team

Three students at MakeUC 2026: core and integration (MacBook Pro), Finder integration and second-Mac testing (MacBook Air), tuning, write-up and video (Windows PC).
