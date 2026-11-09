# AirSign: 5-minute demo script

Used for live judging on 2026-11-08 and kept for reference. For judging on Discord: we screen-share, judges can't touch anything, and 5 minutes of Q&A follow.
Judges score success, failure and limits (Technical Demonstration), so we show all three.

## Roles

| Who | Where | Does |
|---|---|---|
| **Presenter** | Mic | Speaks the lines below and keeps time |
| **Owner** (Tester A) | MacBook Pro, shares screen, right AirPod | Signs; drives Finder and AirSign |
| **Imitator** | Next to the Owner, same right AirPod | Has watched the Owner sign at least 3 times |
| **Second Mac** (B) | MacBook Air with its own enrollment | Live share or the backup clip for 2:45 |

## Setup (15 minutes before)

- [ ] AirSign enrolled with the **right** AirPod. Settings → **Demo mode on**, so the gate lights and the score show (turning it on needs one owner signature or the recovery code). Threshold override at **Reset**.
- [ ] **Sound output set to the AirPods** (Control Center → Sound). Without it, gate 1 can't identify the AirPods and asks you to sign again.
- [ ] The left AirPod is in the case, and the Owner's finger covers the right one's skin sensor.
- [ ] **Webcam overlay of the signing hand:** QuickTime Player → File → New Movie Recording, select the webcam, and drag the window to the bottom-right corner of the shared screen. Or use OBS with a camera source.
- [ ] Desktop has `tax-return.pdf` with **fake** content and a visible first page. The Trash is empty.
- [ ] A `.airsign` copy of the same file is already on the MacBook Air, and the recovery code is on paper.
- [ ] On the MacBook Air: Settings shows **Paired Macs: 0**. If rehearsal paired it, press **Forget paired Macs**, or B's signature will open Tester A's file and 2:45 breaks.
- [ ] A slide or the README's "What we measured" open in a tab for the numbers at 3:15.
- [ ] Discord: share the **window or screen at 1080p**, test once that the judges' view shows the overlay.
- [ ] The backup demo video is ready to share if anything breaks.
- [ ] Rehearse with a timer. **Lockout rule:** 5 failures in a row lock unlocking for 5 minutes, then 15 minutes, 1 hour and 4 hours, and the recovery code is refused while locked. The demo has 2 planned failures. Don't let rehearsal failures carry over into the live demo.

## Script

| Time | On screen | Say |
|---|---|---|
| 0:00 | AirSign home screen, webcam overlay visible | "Passwords leak. Lots of laptops have no fingerprint reader. And a fingerprint is a secret you can never change, and you leave it on every cup you touch. AirSign locks any file on your Mac with something you do instead: you sign in the air while holding one AirPod." |
| 0:35 | Finder: right-click `tax-return.pdf` → **Lock with AirSign** | "Locking is one click, no signature needed, like zipping a file. AirSign encrypts it with its own key, checks the locked copy decrypts correctly, and only then moves the original to the Trash." |
| 0:55 | Open `tax-return.pdf.airsign` in TextEdit: a readable JSON header, then binary | "The top is a readable header: the original name, when it was locked, and the file's key, wrapped twice. Everything after it is AES-GCM ciphertext. The master key that unwraps it never leaves my Mac's Keychain." |
| 1:10 | Right-click `tax-return.pdf.airsign` → **Unlock with AirSign**. **Imitator** presses Space and signs | "My teammate has watched me sign several times. Same AirPods, same bud." *(Wait for the result.)* "Rejected. The lights show how far each part was from my enrollment: grip, size and tempo, and wrist rhythm." *(Read out the reddest light, the highest ratio; don't guess in advance.)* |
| 1:50 | Owner puts the right AirPod in the case, takes the **left** one out and signs | "Now my real signature, but with the other AirPod." *(Rejected.)* "That's gate 1: it has to be the AirPods and the bud I enrolled with. AirPods belong to one person, but computers get shared, so someone at my Mac with their own AirPods is turned away whatever their signature scores. It's a deterrent, not a secret: the Bluetooth ID is readable nearby, so it's never used as a key." |
| 2:10 | Owner swaps back to the right AirPod and signs | "Now me, the right way." *(Accepted, file restored.)* "The score is under my threshold, and the file is back." Open the PDF to show the first page. |
| 2:45 | Second Mac (live or clip): unlock the copied `.airsign` → "locked on a Mac that isn't paired with this one" → **Use recovery code**, leave **Remember on this Mac** unticked → opens | "Someone copied the locked file to another Mac running AirSign with their own signature. It won't open: the key lives in my Mac's Keychain. The recovery code, shown once when I enrolled, opens it anywhere, which is how you get in if you lose your AirPods. If this were my own second Mac, I'd tick Remember on this Mac once, and after that my AirPods and signature would open my files there too. It's not my Mac, so I don't." |
| 3:15 | Numbers table (README "What we measured" or slide) | "We built a logged test lab and ran it on two Macs. First sitting: the owners got in 40 of 41 times; two teammates who watched or practised with a video got in 0 of 81 times, 0 of 111 counting their own signatures. Then the surprise: the same owner a couple of hours later got in only 18 of 25, then 19 of 40. Signatures drift. So AirSign can now add a strong recent signature to your enrollment, without ever loosening the pass mark. After a night's sleep, a simpler signature passed 20 of 20, and two imitators who watched it got in 0 of 50." |
| 3:45 | Threat model table (slide, or README "Security model") | "What we stop: copied files, and someone trying with their own AirPods. What we slow down: someone at your unlocked Mac, or with your stolen AirPods, still has to match your signature, and repeated failures lock it for longer each time, up to four hours. What we don't stop: the signature gates the key, it isn't the key, so someone with your Mac password and the skills to read the Keychain could skip it. And the original stays in the Trash until you empty it, so we never lose your file. It's macOS only, because only Apple exposes AirPods motion." |
| 4:25 | Home screen | "Next: derive the key from the signature itself with a fuzzy extractor, so there's no key to steal. An iPhone relay so Windows and Linux laptops can use it. And a duress signature that opens a decoy." |
| 4:45 | Webcam hand holding the AirPod | "AirSign: your AirPod, your grip, your rhythm. A signature you can change if it ever leaks. Thanks, happy to take questions." |

## If something goes wrong

| Problem | Do this |
|---|---|
| Owner is rejected | "That's the drift we measured: hours after enrolling, I got in 19 times out of 40." Sign again. Don't sign more than twice in a row (lockout). |
| Imitator is **accepted** | Don't hide it: "In the test lab imitators got in 0 of 111 times in the first session and 0 of 50 on the simpler signature, but 1 of 14 in our first prototype; this is exactly the limit we'll talk about." Then continue from 1:50. |
| "Discarded" or no motion | Finger back over the sensor, other AirPod in the case, sign again. Discarded tries don't count as failures. |
| "Set the sound output to your AirPods" | Control Center → Sound → AirPods, sign again. It doesn't count as a failure. |
| Lock/Unlock missing from the right-click menu | System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders, enable them. |
| Locked out | Switch to the backup video: the recovery code is refused while locked, by design. |
| Discord stream freezes | Switch to sharing the backup demo video. |

## Q&A prep

- **Why not Touch ID?** No special hardware; a fingerprint can't be changed if it leaks, a signature can; there's no trace to lift; nothing leaves the Mac. (Touch ID data also stays on the Mac, in the Secure Enclave, so don't claim Apple steals fingerprints.)
- **Can I record your motion and replay it?** The data comes from the real AirPods through macOS. Faking it means running code on your Mac, and at that point the attacker has bigger options.
- **How accurate is it?** In the logged test lab, first sitting: owners 40/41, imitators 0/111 (0/81 after watching or practising). The same owner hours later: 18/25, then 19/40, because signatures drift. Next morning, a simpler signature: owner 20/20, imitators 0/50. Small samples from two imitators, so we show counts.
- **Isn't the key just sitting in the Keychain?** Yes, in this Mac's login Keychain, which doesn't sync. The signature gates it. A fuzzy extractor is the fix, and it's our next step.
- **What if I lose my AirPods?** The recovery code opens any `.airsign` file on any Mac with AirSign. Then enroll new AirPods.
- **I have two Macs. Do I need the code every time?** No. Open one file with the code on the second Mac and tick Remember on this Mac. Only a Mac with its own enrolled signature can pair, the code itself isn't stored, and a fresh enrollment forgets all pairings. On a public Mac, type the code once and nothing is kept.
- **Can someone fake your AirPods' ID?** It's readable over Bluetooth nearby, so gate 1 is only a deterrent: it stops someone casually trying with their own AirPods. It's never used as a key; the signature check still has to pass.
- **Why the Trash?** A bug should never cost a file. Empty the Trash after locking for full protection.
- **Why AirPods?** Many people already own them, and macOS streams their motion even held in the hand: 50 times a second on AirPods Pro 3, 25 on AirPods 4.
- **Is the threshold fixed?** It's set from how consistent your 3 enrollments are. Demo mode can only make it stricter.

## Recording the submission video

- Ask on Discord for the required video length before recording.
- Record this same script with the webcam overlay, and burn in captions for every line.
