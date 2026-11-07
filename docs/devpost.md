# AirSign: Devpost draft

> Before posting:
> - Check every number against `docs/tuning.md` and the final build.
> - Decide whether the app ships `FeatureScale.rotation = 1.5` (the tuning result) or stays at 3, and update "How we built it".
> - If the second-Mac test passed (copied `.airsign` won't open; recovery code does), add "working on two Macs" under Accomplishments.
> - Add the demo video link and screenshots. Delete this box.

**Tagline:** Lock any file on your Mac by signing in the air with an AirPod. Only your AirPod, your grip and your wrist rhythm open it.

## Inspiration

Passwords leak and get reused, and many of us already assume ours are in some breach dump. Plenty of laptops have no fingerprint reader. Some people who care about security don't want to use their fingerprints on any computer, whatever the brand.

A fingerprint is also a secret you can never change. It's left on every cup and screen you touch, and if it leaks, you're stuck with it for life. We wanted a second factor for personal files that:

- needs no special hardware beyond earbuds many people already own
- can be replaced if it ever leaks: just enroll a new signature
- leaves no trace to lift: the way your wrist turns while you sign isn't left on anything
- never leaves your Mac

Then we found that AirPods stream motion data to macOS 50 times a second, even when you hold one in your fingers.

## What it does

1. **Enroll.** Pinch your AirPod so a finger covers its skin sensor, then sign in the air 3 times, about 2 seconds each. AirSign remembers which AirPods and which bud you used, sets a threshold from how consistent you were, and shows a recovery code once.
2. **Lock.** In Finder, right-click any file → **Lock with AirSign**. It becomes `name.airsign`, and the original moves to the Trash only after the locked copy has been decrypted and checked in memory.
3. **Unlock.** Right-click the `.airsign` file → **Unlock with AirSign**, then sign. A match restores the file.

Checks on every unlock:

- **Gate 1 (hard):** the same AirPods (by audio device UID) and the same bud as enrollment. Anything else is rejected before scoring.
- **Score:** one DTW distance over grip angle (gravity direction), size and tempo (acceleration plus duration), and wrist rhythm (gyroscope), compared with your 3 enrolled signatures.
- **Gate lights:** in demo mode, the screen draws your signature and lights the gate that differed most, so you can see why an attempt failed.
- **Lockout:** 5 failures in a row lock unlocking for 5 minutes. Wrong recovery codes count too.
- **Recovery code:** lost your AirPods? The code opens any `.airsign` file on any Mac with AirSign. It's never stored on the Mac.

Nothing is uploaded. AirSign makes no network connections.

## How we built it

- **Native macOS app** in Swift and SwiftUI. Motion comes from `CMHeadphoneMotionManager`, and the AirPods' identity from the CoreAudio output device UID. Finder integration uses macOS Services.
- **Crypto with CryptoKit:**
  - Each file gets its own random 256-bit key and is encrypted with AES-GCM. The file header is authenticated too.
  - That file key is wrapped twice. Once with a master key kept in the macOS Keychain (this-device-only), released only after a signature passes. Once with HPKE (Curve25519, ChaCha20-Poly1305) to a public key derived from the recovery code, so the code works on any Mac.
  - Enrolled signatures are stored encrypted on the Mac.
- **Matcher:**
  - Each sample becomes a 9-number feature: gyro ÷ 3 rad/s, acceleration ÷ 0.5 g, gravity direction.
  - Banded dynamic time warping (25% band) compares two signatures, normalized by their lengths and stretched by 1 + 0.5·|ln duration ratio|.
  - The score is the closest of the 3 templates. The threshold is 1.25 × the worst distance between your own enrollments, and demo mode can only make it stricter.
- **Prototype first:** before writing the app, we built a throwaway spike (Swift motion server plus a web page with live charts) and recorded 116 attempts from owners and imitators.
- **Tuning on a Windows PC:** a Python copy of the matcher replayed those recordings to grid-search the band, duration weight, threshold factor and feature weights. Its scores match the spike: AUC 0.957 vs 0.96 on round 2.
- **Three people, three machines:** a MacBook Pro for the core app, a MacBook Air for Finder integration and a second-Mac test, and a Windows PC for tuning, this write-up and the video.

## Challenges we ran into

- **AirPods aren't a pen.** Only one bud streams at a time, and a hand-held bud stops streaming the moment your finger slips off the in-ear sensor. The recorder discards those attempts instead of counting them as failures.
- **Long signatures are worse.** Our first 6-second signatures were so inconsistent that the owner was rejected almost half the time. About 2 seconds turned out far more stable.
- **Imitators learn.** In round 1, grip angle alone separated owner from imitators perfectly (AUC 1.00). In round 2, after imitators copied the grip, each signal alone dropped to AUC 0.92–0.94, and only the combined score held (0.96). So the gates feed one score instead of each needing a pass.
- **Fair testing.** Imitators who used the other AirPod were always rejected, but that's gate 1, not forgery resistance, so we left those attempts out of the matcher numbers.
- **Free signing only.** With a free Apple ID, we had to make sure rebuilding the app doesn't lose access to its Keychain items.
- **Never lose a file.** Locking writes the `.airsign` file and decrypts it in memory before the original goes anywhere, and the original goes to the Trash rather than being deleted.

## Accomplishments that we're proud of

- A full lock → unlock → recover loop from the Finder right-click menu.
- Honest numbers from 2 rounds of real attempts. Imitators watched the owner sign before trying, and only same-bud attempts count:

| Round | Owner accepted | Imitators accepted | AUC |
|---|---|---|---|
| 1 (imitators hadn't learned the grip) | 25/28 | 0/9 | 0.99 |
| 2 (imitators copied the grip) | 10/10 | 1/14 | 0.96 |

- Tuning found that weighting wrist rhythm twice as heavily (`FeatureScale.rotation` 3 → 1.5) raises round-1 owner acceptance to 27/28 without letting in any more imitators. This matches what round 2 told us: once the grip is copied, rhythm is what's left.
- A threat model we can defend, including what we don't stop.

## What we learned

- Motion biometrics are a "something you do" factor: it's much easier to show what an imitator can't copy than to promise nobody can.
- Combined features beat any single one once attackers adapt. Grip alone fell from AUC 1.00 to 0.93 between rounds; the combined score went from 0.99 to 0.96.
- Measure first: a one-hour spike with real recordings saved us from tuning against made-up data.
- Small samples move fast: with 10–28 attempts per side, one attempt shifts a rate by 3–10 points. We report counts, not just percentages.

## Threat model and limits

| Attacker | Stopped? | Why |
|---|---|---|
| Copies or emails your `.airsign` file | Yes | The master key never leaves your Mac's Keychain |
| Uses your logged-in Mac while you're away | Yes | Needs your AirPods, grip and rhythm; 5 failures lock for 5 minutes |
| Steals your AirPods | Yes | Still needs your grip and rhythm |
| Watches you sign, then imitates | Partly | 1 of 14 skilled attempts got through in round 2, even at the strictest setting we tried |
| Replays recorded motion data | Mostly | Motion comes from the real AirPods via the OS; faking it means running code on your Mac |
| Knows your Mac password and can read the Keychain | No | The signature gates the key; it isn't the key |
| Digs the original out of the Trash | No | The plaintext stays there until you empty the Trash |
| Has your recovery code and the file | No | The code is a master key; keep it offline |
| You lose your AirPods | You're not locked out | Use the recovery code, then enroll new AirPods |

Limits we want to be upfront about:

- **Skilled imitators overlap.** A determined imitator who studies your signature can sometimes pass. AirSign is a second factor for personal files, not a vault.
- **macOS only.** The AirPods motion API exists only on Apple platforms.
- **The signature gates the key; it isn't the key.** Someone with your login password and the skills to read your Keychain could skip the signature.
- **The original stays in the Trash** until you empty it. We chose that over deleting it so a bug can never cost you a file.

## What's next

- **Key from the signature:** a fuzzy extractor so the key is derived from the signature itself, removing the Keychain gap.
- **Other laptops:** use an iPhone as a relay so Windows and Linux machines can read the AirPods.
- **Secure delete:** wipe the original instead of moving it to the Trash.
- **Folders and multiple files,** and a proper Finder extension.
- **More data:** tune each gate with many more owners and imitators.

## Built with

swift, swiftui, cryptokit, core-motion, coreaudio, macos, airpods, python, numpy
