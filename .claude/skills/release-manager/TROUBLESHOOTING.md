# Release troubleshooting

Each entry has the symptom (the text you see), the cause and the fix. Start
with `mise run release:status`. A failed Release run can usually be repeated
with `gh run rerun <run-id> --failed`: publish skips a version that is
already published, and the release job skips a GitHub release that already
exists.

Add an entry for every new failure. Keep the newest entries at the end of
their section.

## release:prepare

**`the working tree has changes; commit them or set them aside first`**
Cause: `prepare` switches to `origin/main` and needs a clean tree.
Fix: commit the work on its branch, or set it aside with a WIP commit.

**`git-cliff could not compute the next version`**
Cause: git-cliff is not on the PATH (it comes from `.mise.toml`).
Fix: `mise install`, then run the task through mise (`mise run release:prepare`).
History: before #32 this fell back to `v0.1.0` without an error.

**`version X is not above the current version Y`**
Cause: no commit since the last tag changes the version (for example only
`chore(release)` or `chore(beads)` commits), or the version you passed is too low.
Fix: if a release is still wanted, pass a version: `mise run release:prepare 0.3.1`.

**`fatal: a branch named 'release/vX.Y.Z' already exists`**
Cause: an earlier `prepare` for the same version.
Fix: close its pull request, then `git branch -D release/vX.Y.Z` and
`git push origin --delete release/vX.Y.Z`, then run `prepare` again.

**The new section has no PR links or `@author`**
Cause: no `GITHUB_TOKEN` and `gh auth token` failed, so git-cliff got no
GitHub data.
Fix: `gh auth login`, close the pull request, delete the branch, run `prepare`
again.

## Release pull request

**A pull request merged to main after `prepare`**
Cause: the new section was made before that merge. The tag will include the
commit, so no later section lists it.
Fix before the release merges: close the release pull request, delete its
branch, run `prepare` again. Fix after: add the line to the released section
in a `docs(changelog)` pull request, then
`gh release edit vX.Y.Z --notes-file <(mise run release:notes X.Y.Z 2>/dev/null)`.

## Release workflow

**No Release run started after the release pull request merged**
Cause: the workflow runs on a push to main only when `moon.mod` changes, or
the workflow is disabled.
Fix: `gh workflow run release.yml --ref main`.

**plan: `CHANGELOG.md has no section for X.Y.Z`**
Cause: `moon.mod` was bumped outside `release:prepare`.
Fix: on a branch, `git cliff --unreleased --tag vX.Y.Z --prepend CHANGELOG.md`,
write the highlights, merge as `chore(release): changelog for vX.Y.Z`, then
`gh workflow run release.yml --ref main`.

**plan or publish: `tag vA does not match moon.mod version B (vB)`**
Cause: a tag was pushed by hand for a commit whose `moon.mod` has another
version.
Fix: with the user's approval, delete that tag (`git push origin --delete vA`)
and release through `release:prepare`.

**test: `version() equals the version in moon.mod` fails**
Cause: `moon.mod` was bumped outside `release:prepare`, so `version()` in
`src/lib.mbt` still returns the old version.
Fix: in the same pull request, set the string that `version()` returns to the
`moon.mod` version.

**validate fails (format, check or tests)**
Cause: main is not releasable.
Fix: fix it on main with a normal pull request (it is then part of the
release), then `gh workflow run release.yml --ref main`.

**publish: `401 Unauthorized`**
Cause: the `MOONCAKES_USER_TOKEN` org secret is missing or expired.
Fix: ask the user to renew the secret, then `gh run rerun <run-id> --failed`.

**publish: `409 Conflict ... is duplicated with an existing version`**
Not an error any more: the publish script reports "already published" and
succeeds. History: krueger-kbg, one tag push started two runs (fixed in #33).

**status: `vX.Y.Z is tagged but has no GitHub release` or `... but mooncakes.io has ...`**
Cause: the run stopped after the tag was made, or a tag was pushed by hand
and its run failed.
Fix: `gh workflow run release.yml --ref vX.Y.Z`.

**status: `moon.mod on main is X but vX has no tag`**
Cause: the Release run for the merge failed or has not finished.
Fix: read the run (`gh run view <run-id> --log-failed`), fix the cause, then
`gh workflow run release.yml --ref main`.

## After the release

**The GitHub release notes are wrong or out of date**
Fix: correct `CHANGELOG.md` in a `docs(changelog)` pull request, then
`gh release edit vX.Y.Z --notes-file <(mise run release:notes X.Y.Z 2>/dev/null)`.

**A broken version is on mooncakes.io**
A version cannot be replaced or deleted. Fix forward: release a patch version
with the fix.
