# AirSign: Devpost text

Based on the text we submitted to Devpost for MakeUC 2026 (Security track), kept for reference and checked against our test records. The full numbers, caveats and test protocol are in the README's [What we measured](../../README.md#what-we-measured) and in [test-sessions.md](test-sessions.md).

**Elevator pitch:** Lock any file or folder on your Mac by signing in the air while holding one AirPod. AES-GCM encryption, no password to leak, no fingerprint to give away, nothing leaves your Mac.

## Inspiration

Passwords leak and get reused. Not every Mac has a fingerprint reader, and some people who care about security don't want to give their fingerprints to any computer. A fingerprint is also a secret you can never change, and you leave it on every cup you touch.

We wanted a second lock for personal files that needs nothing beyond earbuds many people already own, can be replaced if it ever leaks, leaves no trace, and never leaves your Mac. Then we found that macOS streams an AirPod's motion sensors to apps, even while you hold the AirPod in your fingers.

Signing in the air isn't a new idea, and neither is the name: Shao, Yang, Wang and Ma's "AirSign: Smartphone Authentication by Signing in the Air" (*Sensors*, 2020) verifies air signatures with a phone's motion sensors and acoustic echoes. We take the idea somewhere else: no phone in your hand but an AirPod between your fingers, unlocking file keys on a Mac, tested against imitators who studied the owner first.

## What it does

- **Lock:** right-click any file or folder in Finder → **Lock with AirSign**. It becomes a `.airsign` file encrypted with its own AES-GCM key. The original goes to the Trash only after the locked copy is read back, decrypted and matched to the original by SHA-256.
- **Unlock:** right-click the `.airsign` file → **Unlock with AirSign**, hold one AirPod with a finger over its in-ear sensor, and sign in the air.
- **One gate, one score:** your AirPods and the same bud must match, or the attempt is rejected whatever the score. Then one score combines your grip (gravity direction), size and tempo (acceleration and duration) and wrist rhythm (gyroscope), compared with your three enrolled signatures.
- **Signature strength meter:** like a password meter, it refuses signatures that are too short, have too little movement, too few changes of direction, or move mostly one way. Three check signatures must pass before an enrollment is kept.
- **Similarity score:** 100% means identical to your enrollment, 75% is the pass mark. A closeness score, not a probability; outside demo mode it only appears after a pass, so it can't guide an imitator.
- **Follows your drift:** after an unlock at 80% similarity or more, you can add that signature to your enrollment (at most two extra, originals always kept). The pass mark never moves.
- **Recovery code:** a 32-character code, shown once, opens your locked files on any Mac if you lose your AirPods. Changing your signature always needs it.
- **Escalating lockout:** 5 failures in a row lock signing for 5 minutes, then 15 minutes, 1 hour and 4 hours.
- **3-D preview:** drag to turn your signature and see it from any angle.
- No accounts, no cloud, no network code at all.

## How we built it

- **Native macOS app** in Swift and SwiftUI; motion from CoreMotion's `CMHeadphoneMotionManager`; the AirPods' identity from the CoreAudio output device; Finder integration through macOS Services.
- **Matcher:** each sample becomes 9 numbers (rotation rate ÷ 3 rad/s, acceleration ÷ 0.5 g, gravity direction). Banded dynamic time warping (25% Sakoe-Chiba band, normalized by length, with a duration penalty) compares a signature with the enrolled ones; the score is the smallest distance. Each user's pass mark is 1.25 × the largest difference between their own enrolled signatures, so it adapts to how consistent they are.
- **Crypto with CryptoKit:** each file gets a random 256-bit key and AES-GCM, with the readable JSON header authenticated as associated data. The file key is wrapped twice: with a master key in the Mac's login Keychain (locking uses it freely; unlocking only after a signature passes) and with HPKE (X25519, ChaCha20-Poly1305) to a public key derived from the recovery code. Folders are packed with `ditto` and sealed the same way.
- **Process:** a written design and task-by-task plan first, then test-driven development: 62 unit tests on the core. A logged test lab is built into the app, and a Python port of the matcher (checked to give the app's exact scores) runs the analysis. Claude Code and Antigravity were our coding assistants.

## Challenges we ran into

- **Signatures drift.** The same owner, same enrollment, same Mac got in 20/20 right after enrolling, then 18/25 about two hours later and 19/40 after that. Five of those 40 scored worse than the closest imitator, so no threshold alone can fix it. That is why AirSign now offers to add strong recent signatures to your enrollment.
- **Only one bud streams at a time**, and AirPods 4 stream at 25 Hz where AirPods Pro 3 stream at 50 Hz.
- **Being honest with small data.** With two imitators we report counts and Wilson intervals and fixed our decision rules before collecting the data that tests them.

## Accomplishments that we're proud of

- A working Finder workflow: lock and unlock real files and folders with a signature in the air.
- A logged test lab on two Macs. First session: owners got in 40/41 times; two imitators got in 0/81 times after watching or practising with a video (0/111 including their own signatures); the wrong bud or different AirPods 0/30.
- After a night's sleep, a simpler signature passed 20/20, and two imitators who watched the owner sign got in 0/50. Complex signatures take practice and their details are easy to forget; a simpler one is steadier, and the strength meter keeps it from getting too simple.

## What we learned

- In our early prototype tests, once imitators had copied the grip, no single signal told them apart; only the combined score still did.
- A biometric that works right after enrollment can fail hours later; test across sessions, not just within one.
- Small samples move fast, so count, don't claim percentages.

## What's next for AirSign

- Derive the key from the signature itself (a fuzzy extractor) or release it from the Secure Enclave, so there is no readable stored key.
- Enroll across days and measure how much added signatures help over weeks.
- A larger evaluation with more owners and imitators, and a public dataset.
- An iPhone relay so Windows and Linux laptops can use AirPods, and a duress signature that opens a decoy.

## Threat model and limits

Not part of the Devpost submission; kept here because it covers pairing a second Mac, which the submission leaves out.

| Attacker | Stopped? | Why |
|---|---|---|
| Copies or emails your `.airsign` file | Yes | The master key never leaves your Mac's Keychain |
| Gets a file from another Mac you paired | Yes | The paired key sits in that Mac's Keychain and is used only after its AirPods and signature check; the recovery code isn't stored. Pair only on your own user account; on public Macs, type the code once |
| Deletes your settings and re-enrolls to reuse your pairings | Yes | A fresh enrollment makes a new master key and clears every pairing |
| Tries at your Mac with their own AirPods | Yes, at gate 1 | Turned away whatever the score. A deterrent only: the Bluetooth ID is readable nearby, so it's never a key |
| Uses your logged-in Mac while you're away | Partly | Needs your AirPods and a signature close enough to yours; the lockout grows from 5 minutes to 4 hours |
| Steals your AirPods | Partly | They also need your Mac, and then it's the imitation case below |
| Watches you sign, then imitates | Partly | In the test lab, for these two imitators: 0/81 attempts after watching or practising got through in the first session (0/111 with their own signatures), and 0/50 against the owner's simpler signature the next morning; in the prototype's round 2, 1/14 (Wilson 95% interval 1.3–31%) |
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
- **Small, in-house test.** Two owners and two imitators from our team, one person in both roles. One teammate was both an imitator and the person who analysed the results. To limit that, the matcher was frozen before testing, and alternatives were judged by pre-registered rules.

## References

- Y. Shao, T. Yang, H. Wang, J. Ma. "AirSign: Smartphone Authentication by Signing in the Air." *Sensors* 21(1):104, 2020. doi:10.3390/s21010104
- Wilson score interval for every k/n; rule of three for 0/n.
- ISO/IEC 30107-3 for reporting deliberate imitations as attack success rates, apart from the false accept rate.
- A. J. Mansfield and J. L. Wayman, *Best Practices in Testing and Reporting Performance of Biometric Devices*, NPL, 2002: freeze settings before testing.

## Built with

swift, swiftui, macos, coremotion, cryptokit, aes-gcm, hpke, keychain, airpods, dynamic-time-warping, python, github, claude-code, antigravity
