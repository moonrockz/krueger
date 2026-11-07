# OpenSpec

## Shared OpenSpec bundle

`html-design` comes from Mission Control's shared OpenSpec bundle. The pinned
`mission-control-tools` CLI (`.mise.toml`) installs and checks it. The schema,
templates and licenses are generated snapshots; keep repository overrides in
`openspec/config.yaml` and `AGENTS.md`.

- Run `mise run openspec:check` to verify the committed file hashes, the default
  schema and that the lock records the pinned tool version.
- Run `mise run openspec:setup` to regenerate the six core agent skills with
  isolated global preferences.
- Run `mise run openspec:verify` before review. It runs the check, then
  `openspec schema validate html-design` and `openspec validate --all --strict`.
- New designs are offline `design.html` with inline CSS. Existing changes keep
  their schema metadata and original designs, including Markdown designs.
- OpenSpec requirements and change artifacts are committed project documentation.
  Scratch documents remain local under the existing repository rules.

To update the snapshots, change the `mission-control-tools` version in
`.mise.toml`, then run:

```shell
mise install
mise exec -- mission-control-tools openspec install
mise run openspec:verify
```

Commit `.mise.toml`, `openspec/extensions.lock.json` and the changed snapshots.
The CLI is a released binary, so a MoonBit toolchain change cannot break these
commands. See
[the tool guide](https://github.com/moonrockz/mission-control/blob/tools-v0.1.1/apps/tools/README.md).
