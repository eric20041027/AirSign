# AirSign: Devpost draft

> Before posting:
> - Check every number against `docs/tuning.md` and the final build.
> - Decide whether the app ships `FeatureScale.rotation = 1.5` (the tuning result) or stays at 3, and update "How we built it".
> - If the second-Mac test passed (copied `.airsign` won't open; recovery code does), add "working on two Macs" under Accomplishments.
> - Add the test-lab results from `docs/evaluation.md` under Accomplishments, in the same form: "for these imitators, x/n (Wilson 95% interval a–b%)". Keep the prototype numbers as the earlier round.
> - Name check: Shao et al. (2020) already published a system called "AirSign" (see Inspiration). Decide whether to keep the name.
> - Add the demo video link and screenshots. Delete this box.

**Tagline:** Lock any file on your Mac by signing in the air with an AirPod. Only your AirPod, your grip and your wrist rhythm open it.

## Inspiration

Passwords leak and get reused, and many of us already assume ours are in some breach dump. Plenty of laptops have no fingerprint reader. Some people who care about security don't want to use their fingerprints on any computer, whatever the brand.

A fingerprint is also a secret you can never change. It's left on every cup and screen you touch, and if it leaks, you're stuck with it for life. We wanted a second factor for personal files that:

- needs no special hardware beyond earbuds many people already own
- can be replaced if it ever leaks: just enroll a new signature
- leaves no trace to lift: the way your wrist turns while you sign isn't left on anything
- never leaves your Mac

Then we found that AirPods stream motion data to macOS up to 50 times a second (25 on AirPods 4), even when you hold one in your fingers.

Signing in the air isn't a new idea, and neither is the name. Shao, Yang, Wang and Ma's "AirSign: Smartphone Authentication by Signing in the Air" (*Sensors*, 2020) verifies a signature drawn in the air with a smartphone, using the phone's motion sensors plus acoustic echoes. We build on the same idea with three differences:

- no phone in your hand: an AirPod pinched between your fingers
- the signature unlocks file keys on a Mac, rather than unlocking a phone
- our tests pit the owner against imitators who studied them first

## What it does

1. **Enroll.** Pinch your AirPod so a finger covers its skin sensor, then sign in the air 3 times, about 2 seconds each. AirSign remembers which AirPods and which bud you used, sets a threshold from how consistent you were, and shows a recovery code once.
2. **Lock.** In Finder, right-click any file → **Lock with AirSign**. It becomes `name.airsign`, and the original moves to the Trash only after the locked copy has been decrypted and checked in memory.
3. **Unlock.** Right-click the `.airsign` file → **Unlock with AirSign**, then sign. A match restores the file.

Checks on every unlock:

- **Gate 1 (hard):** the same AirPods (by audio device UID) and the same bud as enrollment. AirPods belong to one person, while computers often get shared, so someone who tries with their own AirPods is turned away whatever their signature scores. It's a deterrent check, not a secret: the Bluetooth ID can be read by anyone nearby, so it's never used as an encryption key.
- **Score:** one DTW distance over grip angle (gravity direction), size and tempo (acceleration plus duration), and wrist rhythm (gyroscope), compared with your 3 enrolled signatures.
- **Gate lights:** in demo mode, the screen draws your signature and lights the gate that differed most, so you can see why an attempt failed.
- **Lockout:** 5 failures in a row lock unlocking for 5 minutes, then 15 minutes, 1 hour and 4 hours. Wrong recovery codes count too, and no code is accepted while locked.
- **Recovery code:** lost your AirPods? The code opens any `.airsign` file on any Mac with AirSign. The code itself is never stored.
- **Pairing your other Mac:** open a file from your other Mac once with the recovery code and tick **Remember on this Mac**. From then on, your AirPods and signature on this Mac open files locked on the other one. Only a Mac with its own enrolled signature can pair; on a public Mac you just use the code once and nothing is saved. A fresh enrollment forgets all pairings.

Nothing is uploaded. AirSign makes no network connections.

## How we built it

- **Native macOS app** in Swift and SwiftUI. Motion comes from `CMHeadphoneMotionManager`, and the AirPods' identity from the CoreAudio output device UID. Finder integration uses macOS Services.
- **Crypto with CryptoKit:**
  - Each file gets its own random 256-bit key, and its content is encrypted with AES-GCM.
  - The `.airsign` file starts with a readable JSON header: the original name, when it was locked, and the wrapped keys. The header is authenticated together with the ciphertext, so editing it breaks the file.
  - The file key is wrapped twice. Once with a master key kept in this Mac's login Keychain, which doesn't sync to other devices. Locking uses it without a signature, like zipping a file; unlocking uses it only after a signature passes. Once with HPKE (Curve25519, ChaCha20-Poly1305) to a public key derived from the recovery code, so the code works on any Mac.
  - Pairing stores the key derived from the recovery code (never the code itself) in the second Mac's Keychain, used only after that Mac's AirPods and signature check passes. A fresh enrollment makes a new master key and clears every pairing.
  - Enrolled signatures are stored encrypted on the Mac.
- **Matcher:**
  - Each sample becomes a 9-number feature: gyro ÷ 3 rad/s, acceleration ÷ 0.5 g, gravity direction.
  - Banded dynamic time warping (25% band) compares two signatures, normalized by their lengths and stretched by 1 + 0.5·|ln duration ratio|.
  - The score is the closest of the 3 templates. The threshold is 1.25 × the worst distance between your own enrollments, and demo mode can only make it stricter.
- **Prototype first:** before writing the app, we built a throwaway spike (Swift motion server plus a web page with live charts) and recorded 116 attempts from owners and imitators.
- **Tuning on a Windows PC:** a Python copy of the matcher replayed those recordings to grid-search the band, duration weight, threshold factor and feature weights. It reproduces the prototype's round-2 result exactly: owner 10/10 (Wilson 95% interval 72–100%), and for these imitators 1/14 (1.3–31%).
- **Three people, three machines:** a MacBook Pro for the core app, a MacBook Air for Finder integration and a second-Mac test, and a Windows PC for tuning, this write-up and the video.

## Challenges we ran into

- **AirPods aren't a pen.** Only one bud streams at a time, and a hand-held bud stops streaming the moment your finger slips off the in-ear sensor. The recorder discards those attempts instead of counting them as failures.
- **Long signatures are worse.** With our first 6-second signatures, the owner got in only 8/14 times (Wilson 95% interval 33–79%), even at the prototype's looser threshold. About 2 seconds turned out far more stable.
- **Imitators learn.** In round 1, grip angle alone was enough to tell the owner from these imitators. In round 2, once they had copied the grip, no single signal was, and only the combined score still held. So the gates feed one score instead of each needing a pass.
- **Fair testing.** Imitators who used the other AirPod were always rejected, but that's gate 1, not forgery resistance, so we left those attempts out of the matcher numbers.
- **Free signing only.** With a free Apple ID, we had to make sure rebuilding the app doesn't lose access to its Keychain items.
- **Never lose a file.** Locking writes the `.airsign` file and decrypts it in memory before the original goes anywhere, and the original goes to the Trash rather than being deleted.

## Accomplishments that we're proud of

- A full lock → unlock → recover loop from the Finder right-click menu, plus pairing so your own second Mac opens your files with your signature.
- Honest numbers from 2 prototype rounds of real attempts. The imitators watched the owner sign before trying, and only same-bud attempts count. Every number is for **these imitators**, as x/n with a Wilson 95% interval. A handful of people can't speak for everyone.

| Round | Owner accepted | Imitators accepted |
|---|---|---|
| 1 (imitators hadn't learned the grip) | 25/28 (73–96%) | 0/9 (0–30%) |
| 2 (imitators copied the grip) | 10/10 (72–100%) | 1/14 (1.3–31%) |

- Tuning found that weighting wrist rhythm twice as heavily (`FeatureScale.rotation` 3 → 1.5) raises round-1 owner acceptance to 27/28 (Wilson 95% interval 82–99%), while these imitators still got in 0/9 (0–30%) and 1/14 (1.3–31%) times. This matches what round 2 told us: once the grip is copied, rhythm is what's left.
- A pre-registered test protocol: the app's matcher was frozen before the test lab ran, thresholds for any alternative come from the owners' first session only, and alternatives must beat it on later sessions to replace it.
- A threat model we can defend, including what we don't stop.

## What we learned

- Motion biometrics are a "something you do" factor: it's much easier to show what an imitator can't copy than to promise nobody can.
- Combined features beat any single one once attackers adapt. In round 2, grip alone no longer told owner and imitators apart, but the combined score still let these imitators in only 1/14 times (Wilson 95% interval 1.3–31%).
- Measure first: a one-hour spike with real recordings saved us from tuning against made-up data.
- Small samples move fast: with 10–28 attempts per side, one attempt shifts a rate by 3–10 points. That's why we give counts with Wilson 95% intervals instead of bare percentages: 1/14 could mean anything from about 1% to 31%.

## Threat model and limits

| Attacker | Stopped? | Why |
|---|---|---|
| Copies or emails your `.airsign` file | Yes | The master key never leaves your Mac's Keychain |
| Gets a file from another Mac you paired | Yes | The paired key sits in that Mac's Keychain and is used only after its AirPods and signature check; the recovery code isn't stored. Pair only on your own user account; on public Macs, type the code once |
| Deletes your settings and re-enrolls to reuse your pairings | Yes | A fresh enrollment makes a new master key and clears every pairing |
| Tries at your Mac with their own AirPods | Yes, at gate 1 | Turned away whatever the score. A deterrent only: the Bluetooth ID is readable nearby, so it's never a key |
| Uses your logged-in Mac while you're away | Partly | Needs your AirPods and a signature close enough to yours; the lockout grows from 5 minutes to 4 hours |
| Steals your AirPods | Partly | They also need your Mac, and then it's the imitation case below |
| Watches you sign, then imitates | Partly | In the test lab, for these two imitators, 0/81 attempts after watching or practising got through (0/111 with their own signatures); in the prototype's round 2, 1/14 (Wilson 95% interval 1.3–31%) |
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
- **Gate 1 is a deterrent, not a secret.** An attacker who reads your AirPods' Bluetooth ID nearby learns nothing that unlocks a file; the signature check still has to pass.
- **Small, in-house test.** Two owners and a few imitators, all from our team or nearby. One teammate was both an imitator and the person who analysed the results. To limit that, the matcher was frozen before testing, and alternatives were judged by pre-registered rules.

## What's next

- **Key from the signature:** a fuzzy extractor so the key is derived from the signature itself, removing the Keychain gap.
- **Other laptops:** use an iPhone as a relay so Windows and Linux machines can read the AirPods.
- **Secure delete:** wipe the original instead of moving it to the Trash.
- **Folders and multiple files,** and a proper Finder extension.
- **More data:** tune each gate with many more owners and imitators.

## References

- Y. Shao, T. Yang, H. Wang, J. Ma. "AirSign: Smartphone Authentication by Signing in the Air." *Sensors* 21(1):104, 2020. doi:10.3390/s21010104
- Wilson score interval for every k/n; rule of three for 0/n.
- ISO/IEC 30107-3 for reporting deliberate imitations as attack success rates, apart from the false accept rate.
- A. J. Mansfield and J. L. Wayman, *Best Practices in Testing and Reporting Performance of Biometric Devices*, NPL, 2002: freeze settings before testing.

## Built with

swift, swiftui, cryptokit, core-motion, coreaudio, macos, airpods, python, numpy
