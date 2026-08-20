---
name: search
description: Change library search or comparison-screen change filtering. Use when SearchIndex ranking, limits, or ChangeSearchIndex behaviour is wrong.
---

# Search

`SearchIndex` is capability-agnostic: snapshots, sections, entities, properties. Adding a collector must not require search-code edits.

- Empty or whitespace queries return nothing for snapshot search.
- All terms must match (AND).
- Ranking: exact title > prefix > substring > whole-word haystack. Ties break by newer date, then id.
- `ChangeSearchIndex` empty query returns **all** changes (filter field, not a library search).

Tests: `Tests/Domain/SearchIndexTests.swift` and search invariants. Do not introduce a ranking ML model.
