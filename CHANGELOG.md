# Changelog

What changed in each release of AirSign, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semantic versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-13

AirSign's first release locks a file or folder on a Mac with a signature drawn in the air with one AirPod. A recovery code is the way back. Nothing leaves the Mac. It is built from source.

### Security

- A restored file or folder appears whole or not at all, except on drives that cannot rename without replacing, such as exFAT or FAT: a single file is written straight to its final name. A force-quit during that copy can leave an incomplete file there; the locked file stays and nothing is overwritten.
- At the next unlock in a folder, AirSign removes its own hidden `.airsign-partial-…` folders left there by an interrupted restore, if nothing is using them.
- An unreadable profile or key shows a blocking screen instead of asking you to enroll again, so the master key is kept.
- Reset replaces nothing until you confirm the new recovery code. Cancelling or quitting before then keeps everything.
- Changing the clock no longer ends a cooldown while the Mac has not restarted.
- The test lab, AirPods probe and Keychain self-test are only in lab builds.
- The security model now explains pairing a second Mac.

### Fixed

- The profile file is replaced in one step. The new file has its final permissions before it takes the old one's place.
- A lockout saved by an older build cannot last longer than 4 hours.
- **Forget paired Macs** works even when the pairing keys cannot be read.

### Changed

- Locking and unlocking run in the background, one operation at a time, with a progress line. Other actions are unavailable until the operation ends.
- Items opened while files are being processed wait their turn.

### Upgrading from a build made before 13 November 2026

If the Keychain has no `lockout` item, the first launch starts a one-time cooldown of 4 hours, the longest cooldown. Check whether the item exists with `security find-generic-password -s com.makeuc.airsign -a lockout`. If it is missing, unlock one file with the old build before upgrading.

See [Known limitations in SECURITY.md](SECURITY.md#known-limitations).

[Unreleased]: https://github.com/eric20041027/AirSign/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/eric20041027/AirSign/releases/tag/v0.1.0
