# CLI (`diffuse-dev`)

`diffuse-dev` is a command-line client of the same domain engine the apps use. It imports **no** UI framework. If a command needs new behaviour, add it to a package first, then expose it here.

Source: `Tools/diffuse-dev/`. Nested [Tools/AGENTS.md](../Tools/AGENTS.md). Skill: `capture-cli`. On macOS it uses `MacCapabilityRegistry` (full collector set, including git watch list via `--repos`). Argument parsing is hand-rolled — there is no `swift-argument-parser` ([adr/0004](adr/0004-no-third-party-deps.md)).

```bash
swift run diffuse-dev --help
swift run diffuse-dev version
```

## Why it exists

1. Debugging collectors without clicking through four apps.
2. Proof that capture, diff, validate, export, and the privacy ledger are domain operations.
3. Fixture generation used by `./Scripts/generate-fixtures.sh`.

The CLI does **not** write into the user’s Application Support library unless you point it at a path. `snapshot` captures to stdout or a file you name. `diff` / `inspect` / `validate` read files through `SnapshotCoding` (in memory). That is deliberate: a debug tool should not mutate the app’s history by surprise.

## Commands

| Command | What it does |
| --- | --- |
| `capabilities` | List capabilities on this machine and whether each is available |
| `snapshot [out.json]` | Capture and print or write a snapshot (tags the result `cli`) |
| `inspect <snapshot.json>` | Summarise a snapshot file |
| `diff <before.json> <after.json>` | Compare two snapshot files |
| `validate <snapshot.json>` | `SnapshotValidator` — exit `1` on problems |
| `generate-fixture [ignored]` | Write deterministic fixtures (`--output <dir>`, default `Fixtures/`) |
| `privacy` | Print the generated privacy ledger (Markdown) |
| `version` | Tool version (`1.0.0` today) |

Unknown commands and `--help` print usage and exit `64`.

## Options

| Option | Meaning | Used by |
| --- | --- | --- |
| `--json` | Machine-readable JSON instead of formatted text | `capabilities`, `snapshot`, `diff` |
| `--markdown` | Markdown via `ReportRenderer` | `inspect`, `diff` |
| `--severity <level>` | `informational` \| `notable` \| `significant` \| `critical` | `diff` (filters the text/Markdown report; JSON is unfiltered) |
| `--verbose` | Unchanged entities (`diff`) or full entity/property dump (`inspect`) | `inspect`, `diff` |
| `--repos <a,b,c>` | Git repositories to watch when snapshotting | `capabilities`, `snapshot`, `privacy` |
| `--label <text>` | Label the snapshot being taken | `snapshot` |
| `--pretty` / `--compact` | JSON formatting (`snapshot` / `diff --json`) | |
| `--fail-on-change` | Exit `2` when the diff has any **significant** (or higher) change | `diff` |
| `--output <dir>` | Destination for generated fixtures | `generate-fixture` |

Do not parse snapshot JSON by hand in a command. Use `SnapshotCoding`, `DiffEngine`, `ReportRenderer`, `PrivacyLedger`, `SnapshotValidator`.

## Examples

```bash
# What can this Mac observe right now?
swift run diffuse-dev capabilities
swift run diffuse-dev capabilities --json

# Capture, inspect, validate
swift run diffuse-dev snapshot /tmp/before.json --repos "$HOME/code/Diffuse"
swift run diffuse-dev snapshot /tmp/after.json --label "after lunch" --repos "$HOME/code/Diffuse"
swift run diffuse-dev inspect /tmp/after.json --verbose
swift run diffuse-dev validate /tmp/after.json

# Diff for humans, for a gist, or as a CI gate
swift run diffuse-dev diff /tmp/before.json /tmp/after.json
swift run diffuse-dev diff /tmp/before.json /tmp/after.json --markdown --severity notable
swift run diffuse-dev diff /tmp/before.json /tmp/after.json --json --compact
swift run diffuse-dev diff /tmp/before.json /tmp/after.json --fail-on-change

# Live privacy contract (generated from the catalog, not hand-written)
swift run diffuse-dev privacy
```

`--fail-on-change` is the intended hook for “fail the job if this build environment drifted” (tool versions, volumes). It looks at `summary.significantCount`, not informational battery wobble.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Validation problems, I/O, collector failures surfaced as errors |
| `2` | `--fail-on-change` and the diff contained significant (or higher) changes |
| `64` | Usage (`EX_USAGE`) |

## Tests

There is no separate “CLI integration framework.” Commands that wrap domain types are covered by package and `Tests/` suites. If you add a flag that changes diff or export semantics, put the assertion on `ReportRenderer` / `DiffEngine` / `SnapshotService`, not on captured stdout, unless the flag is genuinely presentation-only (`--pretty` vs `--compact`).
