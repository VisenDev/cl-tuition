#!/usr/bin/env bash
#
# Pre-flight checks for the /make-release skill.
#
# Runs only the *deterministic, mechanical* gating checks: git state, the
# :version in tuition.asd, whether the version tag already exists, and whether
# the matching release-notes file is present, non-empty, and committed.
#
# It deliberately does NOT judge whether the README or release notes are
# *accurate* (that is the skill's human-reviewed step) and it never tags or
# pushes anything.
#
# Exit status:
#   0  all critical checks passed (there may still be WARN items to review)
#   1  one or more critical checks FAILED — do not release
#   2  could not run (not a git repo, cannot read version, etc.)

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not inside a git repository"; exit 2; }
cd "$ROOT" || exit 2

fail=0
warn=0
say()   { printf '%s\n' "$*"; }
pass()  { printf '  [PASS] %s\n' "$*"; }
flunk() { printf '  [FAIL] %s\n' "$*"; fail=1; }
warns() { printf '  [WARN] %s\n' "$*"; warn=1; }

# ---- version + tag ---------------------------------------------------------
VERSION="$(grep -oE ':version[[:space:]]+"[^"]+"' tuition.asd 2>/dev/null | head -1 | grep -oE '"[^"]+"' | tr -d '"')"
if [[ -z "${VERSION:-}" ]]; then
  echo "ERROR: could not read :version from tuition.asd"; exit 2
fi
TAG="v$VERSION"
say "Release version : $VERSION"
say "Release tag     : $TAG"
say ""

# ---- git working tree ------------------------------------------------------
say "Git working tree"
if [[ -z "$(git status --porcelain)" ]]; then
  pass "working tree is clean"
else
  flunk "uncommitted changes present — commit or stash before releasing"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "master" || "$BRANCH" == "main" ]]; then
  pass "on default branch ($BRANCH)"
else
  warns "on branch '$BRANCH' — releases are normally cut from master"
fi

git fetch --quiet origin "$BRANCH" 2>/dev/null || warns "could not fetch origin/$BRANCH"
if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  behind="$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)"
  ahead="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
  if [[ "$behind" -gt 0 ]]; then
    flunk "local $BRANCH is $behind commit(s) behind origin — pull first"
  elif [[ "$ahead" -gt 0 ]]; then
    warns "local $BRANCH is $ahead unpushed commit(s) ahead of origin — push the branch as well as the tag"
  else
    pass "in sync with origin/$BRANCH"
  fi
else
  warns "no origin/$BRANCH to compare against"
fi
say ""

# ---- version tag must not already exist ------------------------------------
say "Version tag"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  flunk "tag $TAG already exists locally — did you forget to bump :version?"
else
  pass "no local tag $TAG"
fi
if git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q "refs/tags/$TAG"; then
  flunk "tag $TAG already exists on origin"
else
  pass "no remote tag $TAG"
fi

LATEST="$(git tag -l 'v*' | sed 's/^v//' | sort -V | tail -1)"
if [[ -n "$LATEST" ]]; then
  newest="$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -1)"
  if [[ "$VERSION" == "$LATEST" || "$newest" != "$VERSION" ]]; then
    warns "version $VERSION is not greater than latest released $LATEST"
  else
    pass "version $VERSION > latest released $LATEST"
  fi
fi
say ""

# ---- release notes ---------------------------------------------------------
say "Release notes (CI uses this file as the GitHub release body)"
NOTES="doc/release-notes/RELEASE-NOTES-$VERSION.md"
if [[ -f "$NOTES" ]]; then
  pass "found $NOTES"
  [[ -s "$NOTES" ]] || flunk "$NOTES is empty"
  if head -5 "$NOTES" | grep -q "$VERSION"; then
    pass "notes reference version $VERSION near the top"
  else
    warns "version $VERSION not found near the top of $NOTES"
  fi
  if git ls-files --error-unmatch "$NOTES" >/dev/null 2>&1; then
    pass "release notes are tracked by git"
  else
    flunk "$NOTES is not tracked by git — git add and commit it"
  fi
else
  flunk "missing $NOTES"
fi
say ""

# ---- README currency (heuristic only) --------------------------------------
say "README currency (heuristic — the skill reviews content separately)"
if [[ -f README.md ]]; then
  others="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' README.md | sort -u | grep -vx "$VERSION" || true)"
  if [[ -n "$others" ]]; then
    warns "README mentions other version-like strings: $(echo "$others" | tr '\n' ' ')— confirm none is a stale 'current version'"
  else
    pass "no conflicting version strings in README"
  fi
else
  warns "no README.md found"
fi
say ""

# ---- summary ---------------------------------------------------------------
if [[ "$fail" -ne 0 ]]; then
  say "RESULT: BLOCKED — fix the [FAIL] items above before releasing."
  exit 1
elif [[ "$warn" -ne 0 ]]; then
  say "RESULT: OK WITH WARNINGS — review the [WARN] items, then proceed."
  exit 0
else
  say "RESULT: ALL CLEAR."
  exit 0
fi
