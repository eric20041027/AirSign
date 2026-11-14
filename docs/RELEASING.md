# Releasing AirSign

Run these commands from the repository root. A release needs the network, GitHub CLI (`gh`) signed in to GitHub, and the tools listed in [CONTRIBUTING.md](../CONTRIBUTING.md).

1. Choose `X.Y.Z` using [semantic versioning](https://semver.org/). Below 1.0, the `.airsign` file format and the Keychain items still do not change without a migration.

2. On a branch, move the entries under `Unreleased` in `CHANGELOG.md` into a new section headed `## [X.Y.Z] - YYYY-MM-DD`, using today's date. Leave `Unreleased` empty. Add `[X.Y.Z]: https://github.com/eric20041027/AirSign/releases/tag/vX.Y.Z` and update the `Unreleased` link to compare `vX.Y.Z...HEAD`. Set `CFBundleShortVersionString` in `airsign/Resources/Info.plist` to `X.Y.Z`. Keep `CFBundleVersion` at `1` for 0.1.0. Change the tag in the README's install command and its sentence about `main`. Open a pull request and include the previewed notes in its description:

   ```bash
   airsign/scripts/release-check.sh X.Y.Z --preview-notes /tmp/airsign-notes.md
   ```

   Write the notes outside the repository and its Git folders, such as `/tmp/airsign-notes.md`. Read them. Preview checks the notes path, origin URL, version and changelog; it does not check whether a release can be made. The changelog date is the day the pull request is written. Do not correct it after the merge, even if the release happens later: that would change the commit that was checked. The tag and GitHub Release have their own dates. For 0.1.0, pull request #18 must merge before the release pull request.

3. After the pull request merges, update `main`:

   ```bash
   git checkout main && git pull --ff-only
   ```

   Run the full release check and write the notes:

   ```bash
   airsign/scripts/release-check.sh X.Y.Z --notes /tmp/airsign-notes.md
   ```

   It requires a clean `main` at origin's current commit, an unused tag, a successful `check` run on that commit, and a passing `airsign/scripts/check.sh --with-test-volume`. It changes no tracked file and never tags, pushes or publishes. If any check fails, fix the cause through a pull request and run the check again. Never tag by hand to get around a failed check.

4. A maintainer decides whether to tag and push this release at this point. Copy the full commit from the check's last line. Use it in place of `<the commit the check printed>` to create the annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "AirSign X.Y.Z" <the commit the check printed>
   ```

   Push the tag:

   ```bash
   git push origin vX.Y.Z
   ```

   Never move or delete a pushed tag.

5. A maintainer makes a separate decision to publish each time. Create the GitHub Release with the checked notes:

   ```bash
   gh release create vX.Y.Z --title "AirSign X.Y.Z" --notes-file /tmp/airsign-notes.md --verify-tag --latest
   ```

   If creating the GitHub Release fails after the tag is pushed, run only this `gh release create` command again with the same notes file. Do not run the check again: it refuses because the tag now exists.

   Nothing is attached to a release. A download that opens with a double-click needs an Apple Developer ID certificate and notarization, which this project does not have, so AirSign is built from source and signed on your own Mac. GitHub adds the source archives itself. The release is marked latest, not as a pre-release.

6. Look at the release page: check the tag, title, notes and latest marker. Look at the README's release badge and follow it to confirm it shows the new release.

   If the released code is wrong, fix it and release a new version.
