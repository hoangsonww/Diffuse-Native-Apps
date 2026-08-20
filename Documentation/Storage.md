# Storage

Snapshots are files on the device that captured them. There is no database. The access pattern is “list summaries, open one, occasionally prune.” A directory of readable JSON means a user can inspect, back up, copy, or delete their own data with tools they already have.

See skill `storage` and `retention`.

## Location

`FileSnapshotStore.defaultDirectory()` resolves to Application Support / `Diffuse` (via `NSHomeDirectory()` on iOS and watchOS, where `homeDirectoryForCurrentUser` is unavailable).

```
Application Support/Diffuse/
  index.json          rebuildable cache of SnapshotSummary rows
  snapshots/
    <snapshot-id>.json
```

The index is a cache. Deleting it is safe; the next open rebuilds from the files. Deleting a snapshot file and leaving a stale index row is repaired on rebuild (`rebuildIndex` skips unreadable JSON instead of taking down the library).

## File store

- Writes are atomic: temp file + replace so an interrupted write cannot leave a half-written snapshot.
- `save` of an existing id throws `StorageError.alreadyExists`. Snapshots are immutable after persist; retake creates a new id.
- `annotate` is the exception: label, note, pin, tags are metadata *about* the observation, not the observation. Entity payloads are not rewritten except for those fields.
- `delete` / `deleteAll` remove files and the index.
- Duplicate keys in a corrupt `index.json` are uniqued rather than crashing.

Do not share a `FileSnapshotStore` across processes. Widgets do not open the store.

## Protocol

`SnapshotStore` is the seam. Core depends only on the protocol.

| Implementation | Used by |
| --- | --- |
| `FileSnapshotStore` | Apps, CLI library, integration tests |
| `InMemorySnapshotStore` | Unit tests, previews, CLI “diff two files” |

Operations: `save`, `snapshot(id:)`, `snapshots(matching:)`, `summaries(matching:)`, `annotate`, `delete`, `deleteAll`, `count`, `storageSize`.

Helpers on the protocol: `latest`, `latestPair` (oldest of the two first, ready for the diff engine), `require` (throws `.notFound`).

## Query

`SnapshotQuery.apply` is the **single** implementation of filtering. Stores must not reimplement it or paging will drift.

Filters: date range (closed), platforms, origins, tags (OR), pinned-only, search text (label, device name, tags), sort (newest first / oldest first), limit, offset.

Ties on `capturedAt` break by identifier so paging is stable.

## Retention

`RetentionPlanner.plan` is a **pure** function over `[SnapshotSummary]`. The settings UI previews “this will delete N snapshots” with the same function the store executes.

Rules:

- Newest snapshot is **never** deleted. Without it there is nothing to compare the next capture against.
- Default policy: 90 days, 1 GiB cap, protects pinned **and** labelled snapshots (empty labels are not protection).
- Protected snapshots do not consume the count/size quota.
- Age is applied before count/size so the recorded reason stays `tooOld` when both apply.
- `SnapshotService.capture` runs retention **after** save so a tight limit cannot eat the snapshot that was just taken.

macOS can offer a longer window than watchOS in the UI; the planner itself is platform-agnostic.

Unlimited policy (`age: forever`, no byte/count cap) is a no-op.

## Coding

`SnapshotCoding` uses a dedicated ISO-8601 formatter with fractional seconds and a stable envelope (`format: diffuse.snapshot`, `schemaVersion`, `exportedAt`, then `snapshot`). See [SnapshotSchema.md](SnapshotSchema.md). Diff files use `format: diffuse.diff`. Export file extension is `.diffuse.json`.

`SnapshotValidator` runs on generate-fixtures, `diffuse-dev validate`, and tests. Structural rules are listed there.

`SnapshotMigrator` is the v1 chain (currently empty). A future format bump adds a step; it does not rewrite files in place as a side effect of listing the timeline.

## Concurrency

`FileSnapshotStore` and `InMemorySnapshotStore` are actors. UI calls `SnapshotService` (also an actor). Capture may run off the main actor; the service is the serialization point.

## What storage does not do

- Encrypt at rest (FileVault / device encryption is that layer)
- Sync ([adr/0008](adr/0008-no-cloud-sync.md))
- Diff (that is `DiffuseDiff`)
- Know what a “volume” is
