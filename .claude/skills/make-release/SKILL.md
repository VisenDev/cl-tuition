---
name: make-release
description: Cut a new tuition release — verify release notes, tuition.asd version, README currency, a clean tree, and a green test suite, then tag vX.Y.Z and push so CI builds the GitHub release. Use when the user says "make a release", "cut a release", "tag a version", "ship a release", or runs /make-release.
---

# make-release

Release a new version of **tuition**. In this repo a release is driven entirely
by a git tag: pushing a `v*` tag triggers `.github/workflows/release.yaml`,
which builds a source tarball and creates the GitHub release using
`doc/release-notes/RELEASE-NOTES-<version>.md` as the release body. Your job is
to make sure everything lines up **before** the tag exists, then create and push
it.

The version comes from `:version` in `tuition.asd`; the tag is `v<version>`.

## Golden rules

- **Never tag or push without explicit user confirmation.** Pushing the tag
  publishes a release — it is outward-facing and hard to reverse.
- **Do not bump the version or write release notes as part of tagging.** Those
  are deliberate pre-release commits. If they are missing, stop and help the
  user prepare them, then start over with a clean tree.
- **Tag the committed HEAD.** The working tree must be clean so the tag captures
  exactly what was reviewed.
- If any check is BLOCKED/FAILED, stop and report — do not work around it.

## Procedure

### 1. Run the deterministic pre-flight checks

Run the bundled script and show the user its full output:

```bash
bash .claude/skills/make-release/scripts/preflight.sh
```

It reads the version, checks the git state (clean tree, branch, in sync with
origin), that the `v<version>` tag does not already exist locally or on origin,
and that `doc/release-notes/RELEASE-NOTES-<version>.md` exists, is non-empty, is
committed, and references the version.

- Exit 1 (**BLOCKED**): report the `[FAIL]` items and stop. Common cases and
  fixes to offer:
  - *Uncommitted changes* → the version bump and/or release notes probably
    aren't committed yet. Help the user commit them (on `master` or via a PR),
    then re-run from step 1.
  - *Tag already exists / version not greater than latest* → the version wasn't
    bumped. Offer to bump `:version` in `tuition.asd` and create the matching
    `RELEASE-NOTES-<version>.md`, commit, then restart.
  - *Missing release notes* → offer to draft `RELEASE-NOTES-<version>.md` from
    the commits since the last tag (see step 3), following the format of the
    previous file in `doc/release-notes/`.
- Exit 0 with `[WARN]` items: surface them and factor them into step 4.

### 2. Run the test suite

CI runs the unit tests on Linux/macOS/Windows and the example tests on Linux.
Reproduce the unit tests locally; they must be 100% green:

```bash
sbcl --non-interactive \
  --eval '(asdf:load-system "tuition/tests")' \
  --eval '(handler-case (progn (tuition-tests:run-tests) (format t "~%RELEASE-TESTS-OK~%")) (error (e) (format t "~%RELEASE-TESTS-FAIL: ~a~%" e) (sb-ext:exit :code 1)))'
```

Require `RELEASE-TESTS-OK` and `Fail: 0`. If anything fails, stop — do not
release. Optionally also run `./test-examples.sh` (slower; needs a PTY and the
ocicl deps) to mirror CI's example check.

### 3. Review release-notes and README *content* (judgment)

The script only checks that files exist — you must confirm they are *accurate*.

List what changed since the last release and check it is reflected:

```bash
LAST=$(git tag -l 'v*' | sed 's/^v//' | sort -V | tail -1)
git log --no-merges --oneline "v${LAST}..HEAD"
```

- Read `doc/release-notes/RELEASE-NOTES-<version>.md` and confirm every notable
  user-facing change above is described, and that it omits CI/CD-only changes
  (repo convention).
- Skim `README.md` for anything the new features made stale (component lists,
  examples, option names, the current version). Point out gaps; offer to fix
  them (which means a new commit → restart from step 1 with a clean tree).

Summarize your findings for the user.

### 4. Confirm

Present a concise summary and get an explicit yes before doing anything
irreversible:

- version and tag (`vX.Y.Z`)
- release-notes file that will become the release body
- test result
- any outstanding `[WARN]` items or README/notes caveats
- whether the branch also needs pushing (preflight flags unpushed commits)

Ask the user to confirm tagging and pushing. Do not continue without a clear
affirmative.

### 5. Tag and push

Only after confirmation. If preflight reported unpushed commits, push the branch
first so `origin/master` matches the tag:

```bash
git push origin master        # only if the branch was ahead of origin
git tag -a "v<version>" -m "Release v<version>"
git push origin "v<version>"
```

Use an annotated tag. Substitute the real version for `<version>`.

### 6. Report

The tag push starts `.github/workflows/release.yaml`. Tell the user the release
is building and link the run:

- Actions: https://github.com/atgreen/cl-tuition/actions

Offer to watch it to completion:

```bash
gh run watch $(gh run list --workflow=release.yaml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```

If the run fails, help diagnose (a common cause is a release-notes filename that
doesn't match the tag version). To undo a mistaken tag before the release
finishes: `git push origin :refs/tags/v<version>` and `git tag -d v<version>`.
