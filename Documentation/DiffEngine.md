# Diff engine

`DiffuseDiff` compares two snapshots and produces a `DiffResult`: a list of `Change` values, a summary, and optional clusters.

It has **no knowledge of specific capabilities**. It reads the schema that travelled with each section. Adding Docker support must not touch this package.

See [adr/0003-schema-driven-diff.md](adr/0003-schema-driven-diff.md) and skill `diff-engine`.

## Pipeline

1. **Normalize** — `SnapshotNormalizer` orders sections and entities so the same logical snapshot hashes the same. Dictionary iteration order must not leak into change ids.
2. **Match sections** by capability id. A section only in the after-snapshot is an addition; only in the before-snapshot is a removal.
3. **Match entities** by `EntityIdentity` (`EntityMatcher`). Unmatched after-entities are additions; unmatched before-entities are removals. Nested children participate the same way.
4. **Compare properties** with `ValueComparator` using each property’s `ComparisonRule`.
5. **Evaluate severity** with `SeverityEvaluator` from the descriptor, with overrides for addition/removal of the entity kind, and escalation (for example a declared-significant version field that made a **major** semver jump becomes critical).
6. **Correlate** with `ChangeCorrelator` so a rename (same identity, new display name) is not reported twice, and so related property changes in a time window can share a cluster.

`ChangeTimeline` runs this pairwise over a run of snapshots (sorted by capture time, input order ignored) and clusters **across** steps so two events a few minutes apart land together even if they were seen in different captures.

## What counts as a change

- A property value that the comparison rule says differs
- An entity that appeared or disappeared
- A section that appeared or disappeared (including status-only changes such as permission loss)

Whitespace-only display names are ignored. A display-name change that is already explained by a property change is not duplicated.

`diff(A, A)` is empty. That is an invariant, not a courtesy. Seeded property tests generate snapshots and assert it, plus: shuffling entities does not change the diff, reverse diffs swap added/removed counts, summary counts match the change list, severity filtering is monotonic.

## Comparison rules

Documented with the schema: [SnapshotSchema.md](SnapshotSchema.md#comparison-rules). The important engine-side facts:

- `ignored` is equal even if one side is absent (noise you chose to record anyway).
- Absence vs presence is otherwise always different, even under a numeric tolerance.
- Relative tolerance uses the larger magnitude; confidence ramps from 0.5 at the threshold to 1.0 at ~3× the threshold so “just over the noise floor” does not look as sure as “disk went from 40 GB to 2 GB.”

## Severity

| Level | Typical use |
| --- | --- |
| Informational | Expected drift: battery, free-space wobble, process counts |
| Notable | Worth seeing if you look |
| Significant | You probably care (tool version, a volume gone) |
| Critical | Identity-level (device model, OS family, major version jump) |

Peak severity on a diff is the maximum of its changes. Widgets show that peak next to `Δ N`.

Reports (`ReportRenderer`) can raise a minimum severity so a paste into a GitHub issue is not a battery diary. `diffuse-dev diff --fail-on-change` exits `2` when `significantCount > 0` — a CI gate for environment drift, not for informational wobble.

## Change identity

`ChangeID` is content-derived from capability + entity identity + property + kind. Two runs of the engine over the same pair produce byte-identical `DiffResult`s. That is why golden fixtures work. Do not put `UUID()` on a change.

## Clustering

Clustering is **interval grouping**, not inference. A Node upgrade at 11:42 and a Docker stop at 11:46 share a window if `DiffOptions.correlationWindow` says so. There is no model that decides they are “related” beyond time and the configured minimum cluster size.

## Stability

- Deterministic given the snapshots and `DiffOptions`
- Independent of entity shuffle
- Repeatable within a process
- Golden files in `Fixtures/diffs/` are the contract; regenerate only with `./Scripts/generate-fixtures.sh` and an explanation

## What the engine will not do

- Call collectors
- Know that `storage.volumes` is storage
- Fetch from the network
- Apply privacy redaction (export does that, using classifications the schema already carries)
- Invent a comparison rule per vendor
