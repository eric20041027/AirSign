# Security policy

AirSign protects files, so we take reports seriously.

## Supported versions

There are no releases yet. Security fixes go to the `main` branch.

## Reporting a vulnerability

Please report privately: open the repository's **Security** tab and choose **Report a vulnerability** (GitHub private vulnerability reporting). Don't open a public issue, pull request or discussion for a vulnerability.

Include what you found, how to reproduce it, the macOS version and AirPods model, and the commit you tested. Never send a real recovery code, `profile.bin` or test-lab logs: they hold secrets or a person's signature motion.

AirSign is maintained by students in their spare time. We aim to reply within 7 days and will tell you what we plan to do and when.

## In scope

- The `.airsign` file format and its cryptography (AES-GCM, HPKE, key wrapping)
- Handling of the master key, the recovery code and paired-Mac keys, and the Keychain items AirSign creates
- The lockout: getting more attempts than it allows
- Accepting a signature or AirPods that should be rejected, beyond the limits documented in the README
- Plaintext or keys left on disk beyond what the README documents

## Known limitations

These are documented design limits, not vulnerabilities (see the README's [Security model](README.md#security-model)):

- Someone using your unlocked Mac is only partly stopped: they still have to match your signature, and the lockout grows to 4 hours. Someone with your stolen AirPods also needs your Mac, and then the same applies.
- An imitator who watched you sign is only partly stopped: in our tests, two imitators who watched once or practised with a video got in 0 of 81 times, a small sample.
- Someone who knows your Mac login password and can read the Keychain can skip the signature: it guards the key, it isn't the key.
- The AirPods check is a deterrent, not a secret: the AirPods' ID can be read nearby, so someone who spoofs it is let through to the signature check, which they still have to pass.
- Anyone with your recovery code and the file can open it: the code is a master key, keep it offline.
- Locking moves the original to the Trash; it stays there in plaintext until you empty the Trash.
- Someone who can use the Mac as the owner can roll the lockout back by copying and restoring AirSign's folder and the Keychain file. A restart followed by a clock change also ends a cooldown.
- A force-quit during a restore can leave a hidden plaintext `.airsign-partial-…` item next to the locked file until AirSign next unlocks something in that folder.
- On a drive that cannot rename without replacing, such as exFAT or FAT, a single restored file is written straight to its final name, so a force-quit during the copy can leave an incomplete file under that name while the locked file stays and nothing is overwritten.
- A paired Mac stores the other Mac's recovery key in its login Keychain. It can open the files the other Mac locked under the recovery code used to pair, after its own signature check. That code stays the same when the other Mac's signature changes. Resetting AirSign there or enrolling from scratch replaces the code: pair again with the new code, and keep the old code for files locked before. Reading that Keychain is as good as having the other Mac's recovery code. On the paired Mac, Settings → **Forget paired Macs** removes the stored keys.
- Three races remain, each needing another process running as the same user to act within microseconds: swapping a scratch folder between the clean-up's checks and its delete; swapping the empty folder that reserves a name on exFAT or FAT; replacing a file between a failed copy's check and its clean-up on exFAT or FAT. That process can already read and delete everything the owner can, so winning the race gives it nothing new. AirSign has no more rights than that process.
