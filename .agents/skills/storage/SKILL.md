---
name: storage
description: Change the snapshot store, SnapshotQuery, index rebuild, or on-disk layout. Use when save/load, paging, corrupt files, or FileSnapshotStore behaviour is involved.
---

# Storage

JSON files plus a rebuildable `index.json`. No database. Core code depends on the `SnapshotStore` protocol so tests can use `InMemorySnapshotStore`.

- Snapshots are immutable after save. Only annotations (`label`, `note`, `isPinned`, `tags`) mutate.
- `SnapshotQuery.apply` is the single filter implementation; stores must not reimplement filtering.
- Duplicate saves throw `StorageError.alreadyExists`. Missing deletes throw `.notFound`.
- Corrupt snapshot files are skipped on `rebuildIndex`, not fatal to the library.
- Writes are atomic (temp file + replace).

Read `Documentation/Storage.md`. Tests: `Tests/Domain/SnapshotServiceAndStoreTests.swift`, Storage package suite.
