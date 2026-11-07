# AirSign: 5-minute demo script

For judging on Discord: we screen-share, judges can't touch anything, and 5 minutes of Q&A follow.
Judges score success, failure and limits (Technical Demonstration), so we show all three.

## Roles

| Who | Where | Does |
|---|---|---|
| **Presenter** | Mic | Speaks the lines below and keeps time |
| **Owner** (Eric) | MacBook Pro, shares screen, right AirPod | Signs; drives Finder and AirSign |
| **Imitator** | Next to the Owner, same right AirPod | Has watched the Owner sign at least 3 times |
| **Second Mac** (B) | MacBook Air with its own enrollment | Live share or the backup clip for 2:45 |

## Setup (15 minutes before)

- [ ] AirSign enrolled with the **right** AirPod. Settings → **Demo mode on**, so the path and gate lights show. Threshold override at **Reset**.
- [ ] **Sound output set to the AirPods** (Control Center → Sound). Without it, gate 1 can't identify the AirPods and asks you to sign again.
- [ ] The left AirPod is in the case, and the Owner's finger covers the right one's skin sensor.
- [ ] **Webcam overlay of the signing hand:** QuickTime Player → File → New Movie Recording, select the webcam, and drag the window to the bottom-right corner of the shared screen. Or use OBS with a camera source.
- [ ] Desktop has `tax-return.pdf` with **fake** content and a visible first page. The Trash is empty.
- [ ] A `.airsign` copy of the same file is already on the MacBook Air, and the recovery code is on paper.
- [ ] On the MacBook Air: Settings shows **Paired Macs: 0**. If rehearsal paired it, press **Forget paired Macs**, or B's signature will open Eric's file and 2:45 breaks.
- [ ] A slide or `docs/tuning.md` open in a tab for the numbers at 3:15.
- [ ] Discord: share the **window or screen at 1080p**, test once that the judges' view shows the overlay.
- [ ] The backup demo video is ready to share if anything breaks.
- [ ] Rehearse with a timer. **Lockout rule:** 5 failures in a row lock unlocking for 5 minutes, and the demo uses 2. Don't let rehearsal failures carry over into the live demo.

## Script

| Time | On screen | Say |
|---|---|---|
| 0:00 | AirSign home screen, webcam overlay visible | "Passwords leak. Lots of laptops have no fingerprint reader. And a fingerprint is a secret you can never change, and you leave it on every cup you touch. AirSign locks any file on your Mac with something you do instead: you sign in the air while holding one AirPod." |
| 0:35 | Finder: right-click `tax-return.pdf` → **Lock with AirSign** | "Locking is one click, no signature needed, like zipping a file. AirSign encrypts it with its own key, checks the locked copy decrypts correctly, and only then moves the original to the Trash." |
| 0:55 | Open `tax-return.airsign` in TextEdit: a readable JSON header, then binary | "The top is a readable header: the original name, when it was locked, and the file's key, wrapped twice. Everything after it is AES-GCM ciphertext. The master key that unwraps it never leaves my Mac's Keychain." |
| 1:10 | Right-click `tax-return.airsign` → **Unlock with AirSign**. **Imitator** presses Space and signs | "My teammate has watched me sign several times. Same AirPods, same bud." *(Wait for the result.)* "Rejected. The light shows which part differed most from my enrollment: grip, size and tempo, or wrist rhythm." *(Read out whichever gate is lit; don't guess in advance.)* |
| 1:50 | Owner takes the **left** AirPod out and signs | "Now my real signature, but with the other AirPod." *(Rejected.)* "That's gate 1: it has to be the AirPods and the bud I enrolled with. AirPods belong to one person, but computers get shared, so someone at my Mac with their own AirPods is turned away before scoring. It's a deterrent, not a secret: the Bluetooth ID is readable nearby, so it's never used as a key." |
| 2:10 | Owner puts the left AirPod back, signs with the right one | "Now me, the right way." *(Accepted, file restored.)* "The score is under my threshold, and the file is back." Open the PDF to show the first page. |
| 2:45 | Second Mac (live or clip): unlock the copied `.airsign` → "locked on a Mac that isn't paired with this one" → **Use recovery code**, leave **Remember on this Mac** unticked → opens | "Someone copied the locked file to another Mac running AirSign with their own signature. It won't open: the key lives in my Mac's Keychain. The recovery code, shown once when I enrolled, opens it anywhere, which is how you get in if you lose your AirPods. If this were my own second Mac, I'd tick Remember on this Mac once, and after that my AirPods and signature would open my files there too. It's not my Mac, so I don't." |
| 3:15 | Numbers table (`docs/tuning.md` or slide) | "We tested with real imitators who watched the owner first, and only counted same-AirPod attempts. Round 2, after they'd learned the grip: I got in 10 out of 10, imitators 1 out of 14. So a skilled imitator can sometimes pass. That's why AirSign is a second factor for personal files, not a vault." |
| 3:45 | Threat model table (slide or Devpost draft) | "What we stop: stolen files, someone at your unlocked Mac, stolen AirPods, and five failures lock it for five minutes. What we don't stop: the signature gates the key, it isn't the key, so someone with your Mac password and the skills to read the Keychain could skip it. And the original stays in the Trash until you empty it, so we never lose your file. It's macOS only, because only Apple exposes AirPods motion." |
| 4:25 | Home screen | "Next: derive the key from the signature itself with a fuzzy extractor, so there's no key to steal. An iPhone relay so Windows and Linux laptops can use it. Secure delete instead of the Trash." |
| 4:45 | Webcam hand holding the AirPod | "AirSign: your AirPod, your grip, your rhythm. A signature you can change if it ever leaks. Thanks, happy to take questions." |

## If something goes wrong

| Problem | Do this |
|---|---|
| Owner is rejected | "That happens: in our tests I got in 35 times out of 38." Sign again. Don't sign more than twice in a row (lockout). |
| Imitator is **accepted** | Don't hide it: "That's the overlap we measured, 1 in 14. This is exactly the limit we'll talk about." Then continue from 1:50. |
| "Discarded" or no motion | Finger back over the sensor, other AirPod in the case, sign again. Discarded tries don't count as failures. |
| "Set the sound output to your AirPods" | Control Center → Sound → AirPods, sign again. It doesn't count as a failure. |
| Lock/Unlock missing from the right-click menu | System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders, enable them. |
| Locked out | Use the recovery code to show the unlock, and say so. |
| Discord stream freezes | Switch to sharing the backup demo video. |

## Q&A prep

- **Why not Touch ID?** No special hardware; a fingerprint can't be changed if it leaks, a signature can; there's no trace to lift; nothing leaves the Mac. (Touch ID data also stays on the Mac, in the Secure Enclave, so don't claim Apple steals fingerprints.)
- **Can I record your motion and replay it?** The data comes from the real AirPods through macOS. Faking it means running code on your Mac, and at that point the attacker has bigger options.
- **How accurate is it?** Two rounds of real attempts. Round 1: owner 25/28, imitators 0/9. Round 2: owner 10/10, imitators 1/14. Small samples, so we show counts.
- **Isn't the key just sitting in the Keychain?** Yes. The signature gates it, this-device-only. A fuzzy extractor is the fix, and it's our next step.
- **What if I lose my AirPods?** The recovery code opens any `.airsign` file on any Mac with AirSign. Then enroll new AirPods.
- **I have two Macs. Do I need the code every time?** No. Open one file with the code on the second Mac and tick Remember on this Mac. Only a Mac with its own enrolled signature can pair, the code itself isn't stored, and a fresh enrollment forgets all pairings. On a public Mac, type the code once and nothing is kept.
- **Can someone fake your AirPods' ID?** It's readable over Bluetooth nearby, so gate 1 is only a deterrent: it stops someone casually trying with their own AirPods. It's never used as a key; the signature check still has to pass.
- **Why the Trash?** A bug should never cost a file. Secure delete is on the list.
- **Why AirPods?** Many people already own them, and macOS streams their motion at 50 Hz, even held in the hand.
- **Is the threshold fixed?** It's set from how consistent your 3 enrollments are. Demo mode can only make it stricter.

## Recording the submission video

- Ask on Discord for the required video length before recording.
- Record this same script with the webcam overlay, and burn in captions for every line.
