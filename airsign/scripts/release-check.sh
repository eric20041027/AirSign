#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'release check failed: %s\n%s\n' "$1" "$2" >&2
  exit 1
}

usage() {
  fail usage "Usage: $0 <version> [--notes <file> | --preview-notes <file>] (version: X.Y.Z)."
}

case "$#" in
  1) ;;
  3)
    case "$2" in
      --notes|--preview-notes) [[ -n "$3" ]] || usage ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
MODE="${2:-}"
NOTES_FILE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

if [[ -n "$MODE" ]]; then
  [[ ! -L "$NOTES_FILE" && ( ! -e "$NOTES_FILE" || -f "$NOTES_FILE" ) ]] ||
    fail usage "Choose a regular notes file, not a directory or symbolic link."
  NOTES_DIR="$(cd "$(dirname "$NOTES_FILE")" 2>/dev/null && pwd -P)" ||
    fail usage "Create the notes file's parent folder first."
  NOTES_PATH="$NOTES_DIR/$(basename "$NOTES_FILE")"
  case "$NOTES_PATH" in
    "$REPO_ROOT/.git"|"$REPO_ROOT/.git/"*) fail usage "Write notes outside Git's own files." ;;
  esac
  case "$NOTES_PATH" in
    "$REPO_ROOT/"*)
      if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$NOTES_PATH" >/dev/null 2>&1; then
        fail usage "Choose an untracked notes file so no tracked file is changed."
      else
        [[ "$?" == 1 ]] || fail usage "Cannot check whether the notes file is tracked."
      fi
      ;;
  esac
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$REPO_ROOT/airsign/Resources/Info.plist" 2>/dev/null)" ||
  fail version "Cannot read CFBundleShortVersionString from airsign/Resources/Info.plist."
[[ "$PLIST_VERSION" == "$VERSION" ]] ||
  fail version "CFBundleShortVersionString is $PLIST_VERSION; expected $VERSION."

CHANGELOG_BODY="$(awk -v version="$VERSION" '
  BEGIN { prefix = "## [" version "] - " }
  {
    if ($0 ~ /^## /) in_unreleased = 0
    if ($0 == "## [Unreleased]") {
      unreleased++
      in_unreleased = 1
    } else if (in_unreleased && $0 !~ /^[[:space:]]*$/) dirty = 1

    if ($0 ~ /^## \[/ || $0 ~ /^\[[^]]+\]:[[:space:]]*http/) capture = 0
    if (index($0, prefix) == 1 &&
        substr($0, length(prefix) + 1) ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
      releases++
      capture = 1
      next
    }
    if (capture) lines[++count] = $0
  }
  END {
    if (unreleased != 1 || releases != 1 || dirty) exit 1
    first = 1
    last = count
    while (first <= last && lines[first] ~ /^[[:space:]]*$/) first++
    while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print lines[i]
  }
' "$REPO_ROOT/CHANGELOG.md" 2>/dev/null)" ||
  fail changelog "Use exactly one ## [$VERSION] - YYYY-MM-DD heading and leave ## [Unreleased] empty."

write_notes() {
  local temporary
  temporary="$(mktemp "$NOTES_PATH.XXXXXX" 2>/dev/null)" ||
    fail usage "Choose a writable notes file."
  # Replace the destination, so a hard link cannot change a tracked file.
  if ! {
    printf '%s\n\n' "$CHANGELOG_BODY" &&
    cat <<EOF
## Install

Requirements: a Mac with Apple silicon and macOS 14 or later; AirPods with head tracking (tested with AirPods Pro 3 and AirPods 4); Xcode 16 or later with an Apple Development certificate (Xcode → Settings → Accounts → Manage Certificates → + → Apple Development).

\`\`\`bash
git clone --branch v$VERSION --depth 1 https://github.com/eric20041027/AirSign.git
cd AirSign/airsign
swift test               # the core: matcher, crypto, file locking, lockout
scripts/install.sh       # builds, signs, installs to ~/Applications, registers the Finder items
\`\`\`

No Apple Development certificate? Run \`AIRSIGN_ADHOC=1 scripts/install.sh\` instead; macOS may then ask for your password after each rebuild.

## Why there is no app to download

A download that opens with a double-click needs an Apple Developer ID certificate and notarization, which this project does not have, so AirSign is built from source and signed on your own Mac.
EOF
  } > "$temporary" 2>/dev/null; then
    rm -f "$temporary"
    fail usage "Cannot write the notes file; check its folder and free space."
  fi
  if ! mv -f "$temporary" "$NOTES_PATH" 2>/dev/null; then
    rm -f "$temporary"
    fail usage "Cannot replace the notes file; check its permissions."
  fi
}

if [[ "$MODE" == --preview-notes ]]; then
  write_notes
  printf 'Notes written to %s. This was a preview: the release was not checked.\n' "$NOTES_FILE"
  exit 0
fi

WORKING_TREE="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ||
  fail "working tree" "Cannot read git status; run this script from a Git checkout."
[[ -z "$WORKING_TREE" ]] || fail "working tree" "Commit or remove all changes before checking a release."

BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
  fail branch "Check out main before checking a release."
[[ "$BRANCH" == main ]] || fail branch "Check out main before checking a release."
COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD 2>/dev/null)" ||
  fail branch "Cannot read the commit on main."
SHORT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short "$COMMIT" 2>/dev/null)" ||
  fail branch "Cannot read the short commit on main."
REMOTE_MAIN="$(git -C "$REPO_ROOT" ls-remote origin refs/heads/main 2>/dev/null)" ||
  fail network "Cannot read origin's main; check your connection and origin URL, then try again."
[[ "$REMOTE_MAIN" == "$COMMIT"$'\trefs/heads/main' ]] ||
  fail branch "main must point at the same commit as origin's main; run git pull --ff-only."

if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/tags/v$VERSION" 2>/dev/null; then
  fail tag "The local tag v$VERSION already exists; choose an unused version."
else
  [[ "$?" == 1 ]] || fail tag "Cannot read local tags."
fi
REMOTE_TAG="$(git -C "$REPO_ROOT" ls-remote origin "refs/tags/v$VERSION" 2>/dev/null)" ||
  fail network "Cannot read origin's tags; check your connection and origin URL, then try again."
[[ -z "$REMOTE_TAG" ]] || fail tag "The tag v$VERSION already exists on origin; choose an unused version."

command -v gh >/dev/null 2>&1 || fail gh "Install the GitHub CLI (gh), sign in with gh auth login, then try again."
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" ||
  fail network "Cannot read origin's URL; check git remote -v, then try again."
REPOSITORY="${ORIGIN_URL%/}"
REPOSITORY="${REPOSITORY%.git}"
case "$REPOSITORY" in
  https://*|http://*|ssh://*|git://*)
    REPOSITORY="${REPOSITORY#*://}"
    REPOSITORY="${REPOSITORY#*/}"
    ;;
  *@*:*) REPOSITORY="${REPOSITORY#*:}" ;;
  *) fail ci "Cannot find owner/name in origin's URL; use a GitHub HTTPS or SSH URL." ;;
esac
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail ci "Cannot find owner/name in origin's URL; use a GitHub HTTPS or SSH URL."
CHECK_RUNS="$(gh api "repos/$REPOSITORY/commits/$COMMIT/check-runs" --paginate \
  --jq '.check_runs[] | select(.name == "check") | [.id, .status, .conclusion] | @tsv' 2>/dev/null)" ||
  fail network "Cannot read GitHub checks; run gh auth status, check your connection, then try again."
# A rerun must succeed too; an older successful run cannot approve a newer failure.
awk '
  $1 ~ /^[0-9]+$/ && $1 + 0 > latest { latest = $1; status = $2; conclusion = $3 }
  END { exit !(latest && status == "completed" && conclusion == "success") }
' <<< "$CHECK_RUNS" || fail ci "The latest check run named check must be completed with conclusion success on $COMMIT."

"$SCRIPT_DIR/check.sh" --with-test-volume 2>&1 ||
  fail checks "airsign/scripts/check.sh --with-test-volume did not pass; fix its reported failure and try again."
if [[ "$MODE" == --notes ]]; then
  write_notes
fi
printf 'Ready to release %s from %s.\n' "$VERSION" "$SHORT_COMMIT"
