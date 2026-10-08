---
name: release-manager
description: Runs, troubleshoots and improves krueger's release process (release pull request, CHANGELOG.md, Release workflow, mooncakes.io, GitHub release). Use when the user wants to cut, prepare or publish a release, write release highlights, check release status, fix a failed or stuck release, or improve the release process.
---

# Release manager

The process is in AGENTS.md > Release Process. The tools are the
`release:*` mise tasks (`scripts/release.mbtx`, `cliff.toml`,
`.github/workflows/release.yml`). This skill runs them in order, checks each
result, and makes the process better after every release.

Start every session with `mise run release:status`. It prints `ok:`, `info:`
and `problem:` lines, and each problem names its fix command. It exits 1 when
there is a problem.

## Release

Copy this checklist and tick it off:

```
- [ ] 1. Preflight
- [ ] 2. Track the release in bd
- [ ] 3. Prepare the release pull request
- [ ] 4. Write the highlights
- [ ] 5. Merge
- [ ] 6. Watch the Release run
- [ ] 7. Verify
- [ ] 8. Retrospective
```

1. **Preflight.** `mise run release:status` must have no problem. The
   working tree must be clean, `gh auth status` must pass, and the latest CI
   run on main must be green (`gh run list --branch main --workflow ci.yml
   --limit 1`). Show the user `mise run release:version` and the commits since
   the last tag (`git log --oneline $(git describe --tags --abbrev=0)..origin/main`).
   If there are open pull requests the user wants in this release, merge them
   first.
2. **Track.** `bd create "Release vX.Y.Z" -t chore -l release --json`, then
   `bd update <id> --claim`. Record what happens in this issue's notes.
3. **Prepare.** Get the user's approval, because this pushes a branch and
   opens a pull request. Then run `mise run release:prepare` (add a version to
   override git-cliff, for example `1.0.0`).
4. **Highlights.** In `CHANGELOG.md` on `release/vX.Y.Z`, replace the
   highlights comment with 2–5 plain sentences: what a user can now do, what
   breaks and how to migrate. Read the bodies of the included pull requests
   (`gh pr view <n> --json body`) for this. Reword generated lines that are
   unclear. If `prepare` warned about breaking commits without a
   `BREAKING CHANGE:` footer, rewrite their lines to say what breaks. Commit
   as `chore(release): highlights for vX.Y.Z` and push. Run
   `mise run release:refresh` to put the notes into the pull request body.
   Check the result with `mise run release:notes X.Y.Z`. Ask the user to
   review the text.
5. **Merge.** Get the user's approval. Make sure no other pull request merged
   to main after `prepare` (`git log release/vX.Y.Z..origin/main` is empty);
   if one did, see TROUBLESHOOTING.md. Then `gh pr merge <n> --squash`.
6. **Watch.** `gh run list --workflow release.yml --limit 1`, then
   `gh run watch <run-id> --exit-status`. The jobs are plan, validate,
   publish and release.
7. **Verify.** `mise run release:status` must say `vX.Y.Z is released`. Open
   the GitHub release and read the notes.
8. **Retrospective.** Do "Improve the process" below, then close the bd issue
   with a one-line outcome (`bd close <id> --reason "..."`) and `bd sync`.

## Troubleshoot

1. Run `mise run release:status` and read the latest Release run
   (`gh run view <run-id> --log-failed`).
2. Find the symptom in [TROUBLESHOOTING.md](TROUBLESHOOTING.md) and apply its
   fix. Every fix is safe to repeat: publish skips a published version, and
   the release job skips an existing GitHub release.
3. If the symptom is not there, find the cause before you change anything
   (reproduce, then read the script or the workflow). Then add the case to
   TROUBLESHOOTING.md.

Do not delete or move a pushed tag, and do not delete a GitHub release,
without the user's explicit approval. A mooncakes.io version cannot be
replaced; release a new patch version instead.

## Improve the process

After every release and after every incident:

1. Ask what was slow, unclear, manual or wrong. Read the bd notes of this
   release and of earlier ones (`bd list -l release --status closed`).
2. Fix the cause at the lowest level that works, in this order:
   - a check or a step in `scripts/release.mbtx`, with a scenario in
     `scripts/features/release.feature`. A deterministic check is better than
     a written warning;
   - `cliff.toml` or `.github/workflows/release.yml`;
   - AGENTS.md > Release Process, then this skill.
3. Add each new failure mode to TROUBLESHOOTING.md: symptom, cause, fix.
4. Store a lesson that must outlive the session with
   `bd remember "..." --key release-<topic>`. File bigger work as a bd issue
   with label `release`.
5. Ship the change in its own pull request, never in the release pull
   request. Keep this file under 100 lines; move detail to TROUBLESHOOTING.md.
