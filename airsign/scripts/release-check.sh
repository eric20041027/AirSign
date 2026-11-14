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
    fail notes "Choose a regular notes file, not a directory or symbolic link."
  NOTES_DIR="$(cd -- "$(dirname "$NOTES_FILE")" 2>/dev/null && pwd -P)" ||
    fail notes "Create the notes file's parent folder first."
  NOTES_PATH="$NOTES_DIR/$(basename "$NOTES_FILE")"
  GIT_TOPLEVEL="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)" ||
    fail notes "Cannot find the repository folder."
  GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" ||
    fail notes "Cannot find the Git directory."
  GIT_COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)" ||
    fail notes "Cannot find the common Git directory."
  for PROTECTED_DIR in "$GIT_TOPLEVEL" "$GIT_DIR" "$GIT_COMMON_DIR"; do
    PROTECTED_DIR="$(cd "$REPO_ROOT" && cd -- "$PROTECTED_DIR" 2>/dev/null && pwd -P)" ||
      fail notes "Cannot resolve the repository or its Git folders."
    case "$NOTES_PATH" in
      "$PROTECTED_DIR"|"$PROTECTED_DIR/"*)
        fail notes "Write notes outside the repository and its Git folders."
        ;;
    esac
  done
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

read_repository() {
  local read_failure="$1" parse_failure="$2" origin_url
  origin_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" ||
    fail "$read_failure" "Cannot read origin's URL; check git remote -v, then try again."
  REPOSITORY="${origin_url%/}"
  REPOSITORY="${REPOSITORY%.git}"
  case "$REPOSITORY" in
    https://*|http://*|ssh://*|git://*)
      REPOSITORY="${REPOSITORY#*://}"
      REPOSITORY="${REPOSITORY#*/}"
      ;;
    *@*:*) REPOSITORY="${REPOSITORY#*:}" ;;
    *) fail "$parse_failure" "Cannot find owner/name in origin's URL; use a GitHub HTTPS or SSH URL." ;;
  esac
  [[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    fail "$parse_failure" "Cannot find owner/name in origin's URL; use a GitHub HTTPS or SSH URL."
}

write_notes() {
  local temporary
  temporary="$(mktemp "$NOTES_PATH.XXXXXX" 2>/dev/null)" ||
    fail usage "Choose a writable notes file."
  # Replace the destination, so a hard link cannot change a tracked file.
  if ! {
    printf '%s\n\n' "$CHANGELOG_BODY" | awk -v base="https://github.com/$REPOSITORY/blob/v$VERSION/" '
      {
        line = $0
        output = ""
        if (match(line, /^[[:space:]]*\[[^]]+\]:[[:space:]]*<?/)) {
          output = substr(line, 1, RLENGTH)
          line = substr(line, RLENGTH + 1)
          if (line !~ /^(https?:\/\/|#|mailto:)/) output = output base
        }
        while (match(line, /\]\([[:space:]]*<?/)) {
          output = output substr(line, 1, RSTART + RLENGTH - 1)
          line = substr(line, RSTART + RLENGTH)
          if (line !~ /^(https?:\/\/|#|mailto:)/) output = output base
        }
        print output line
      }
    ' &&
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
  read_repository notes notes
  write_notes
  printf 'Notes written to %s. This was a preview: the release was not checked.\n' "$NOTES_FILE"
  exit 0
fi

WORKING_TREE="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all 2>/dev/null)" ||
  fail "working tree" "Cannot read git status; run this script from a Git checkout."
[[ -z "$WORKING_TREE" ]] || fail "working tree" "Commit or remove all changes before checking a release."

BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
  fail branch "Check out main before checking a release."
[[ "$BRANCH" == main ]] || fail branch "Check out main before checking a release."
COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD 2>/dev/null)" ||
  fail branch "Cannot read the commit on main."
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
read_repository network ci
# Select the newest run across all pages, including reruns.
CHECK_RUNS="$(gh api "repos/$REPOSITORY/commits/$COMMIT/check-runs" --paginate \
  --jq '.check_runs[] | select(.name == "check") | "\(.id) \(.status) \(.conclusion)"' && printf '\001')" ||
  fail network "Cannot read GitHub checks; run gh auth status, check your connection, then try again."
# Preserve extra trailing lines; remove only the marker and one line ending.
CHECK_RUNS="${CHECK_RUNS%$'\001'}"
CHECK_RUNS="${CHECK_RUNS%$'\n'}"
LATEST_CHECK="$(printf '%s\n' "$CHECK_RUNS" | LC_ALL=C awk '
  $0 !~ /^[0-9]+ [a-z0-9_]+ [a-z0-9_]+$/ { invalid = 1; next }
  {
    id = $1
    sub(/^0+/, "", id)
    # Compare decimal integers without losing precision on large IDs.
    if (NR == 1 || length(id) > length(latest_id) ||
        (length(id) == length(latest_id) && ("x" id) > ("x" latest_id))) {
      latest_id = id
      latest_result = $2 " " $3
    }
  }
  END {
    if (invalid) exit 1
    print latest_result
  }
')" &&
[[ "$LATEST_CHECK" == 'completed success' ]] ||
  fail ci "The latest check run named check must return completed success on $COMMIT. Reply:
${CHECK_RUNS:-<empty>}"

"$SCRIPT_DIR/check.sh" --with-test-volume 2>&1 ||
  fail checks "airsign/scripts/check.sh --with-test-volume did not pass; fix its reported failure and try again."
WORKING_TREE="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all 2>/dev/null)" ||
  fail "working tree" "Cannot read git status after the local check."
[[ -z "$WORKING_TREE" ]] || fail "working tree" "The working tree changed during the check; run it again from a clean tree."
BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
  fail branch "Check out main before checking a release."
[[ "$BRANCH" == main ]] || fail branch "The branch changed during the check; check out main and run it again."
CURRENT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD 2>/dev/null)" ||
  fail branch "Cannot read the commit after the local check."
[[ "$CURRENT_COMMIT" == "$COMMIT" ]] || fail branch "main moved during the check; run it again."
if [[ "$MODE" == --notes ]]; then
  write_notes
fi
printf 'Ready to release %s from %s.\n' "$VERSION" "$COMMIT"
