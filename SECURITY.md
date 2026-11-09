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
- Accepting a signature or AirPods that should be rejected, beyond the rates reported in the README
- Plaintext or keys left on disk beyond what the README documents

## Known limitations

These are documented design limits, not vulnerabilities (see the README's [Security model](README.md#security-model)):

- Someone using your unlocked Mac, or with your stolen AirPods, is only partly stopped: they still have to match your signature, and the lockout grows to 4 hours.
- A skilled imitator who watched you sign is only partly stopped: 0/81 such attempts got in during our tests, a small sample.
- Someone who knows your Mac login password and can read the Keychain can skip the signature: it guards the key, it isn't the key.
- Anyone with your recovery code and the file can open it: the code is a master key, keep it offline.
- Locking moves the original to the Trash; it stays there in plaintext until you empty the Trash.
